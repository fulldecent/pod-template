require 'fileutils'
require 'colored'

module Pod
  class TemplateConfigurator

    attr_reader :pod_name, :pods_for_podfile, :prefixes, :test_example_file, :username, :email

    def user_name
      (ENV['GIT_COMMITTER_NAME'] || `git config user.name`).strip
    end

    def user_email
      (ENV['GIT_COMMITTER_EMAIL'] || `git config user.email`).strip
    end

    def year
      Time.now.year.to_s
    end

    def date
      Time.now.strftime "%Y-%m-/%d"
    end

    def podfile_path
      'Example/Podfile'
    end

    def initialize(pod_name)
      @pod_name = pod_name
      @pods_for_podfile = []
      @prefixes = []
      @message_bank = MessageBank.new(self)
    end

    #----------------------------------------#

    def run
      @message_bank.welcome_message
      prepare_staging_directory

      framework = self.ask_with_answers("What language do you want to use?", ["Swift", "ObjC"]).to_sym
      case framework
        when :swift
          ConfigureSwift.perform(configurator: self)

        when :objc
          ConfigureObjC.perform(configurator: self)
      end

      replace_variables_in_files
      rename_template_files
      add_pods_to_podfile
      customise_prefix
      run_pod_install
      initialize_git_repo
      finalize_staging_directory

      @message_bank.farewell_message
    end

    def prepare_staging_directory
      [".git", "configurator", "spec", ".gitignore", ".travis.yml", "configure", "Gemfile", "LICENSE", "Rakefile", "README.md", ].each do |asset|
        `rm -rf #{asset}`
      end
      FileUtils.cp_r 'templates/baseline/.', '.'
    end

    def replace_variables_in_files
      file_names = ['LICENSE', 'README.md', 'PROJECT.podspec', '.travis.yml', 'PROJECT.xcworkspace/contents.xcworkspacedata', podfile_path]
      file_names.each do |file_name|
        text = File.read(file_name)
        text.gsub!("${POD_NAME}", @pod_name)
        text.gsub!("PROJECT", @pod_name)
        text.gsub!("${REPO_NAME}", @pod_name.gsub('+', '-'))
        text.gsub!("${USER_NAME}", user_name)
        text.gsub!("${USER_EMAIL}", user_email)
        text.gsub!("${YEAR}", year)
        text.gsub!("${DATE}", date)
        File.open(file_name, "w") { |file| file.puts text }
      end
    end

    def rename_template_files
      # Move schemes
      FileUtils.mv "PROJECT.xcodeproj/xcshareddata/xcschemes/PROJECT.xcscheme", "PROJECT.xcodeproj/xcshareddata/xcschemes/#{pod_name}.xcscheme"

      # Move project files
      FileUtils.mv "PROJECT.podspec", "#{pod_name}.podspec"
      FileUtils.mv "PROJECT.xcodeproj", "#{pod_name}.xcodeproj"
      FileUtils.mv "PROJECT.xcworkspace", "#{pod_name}.xcworkspace"
    end

    def add_pods_to_podfile
      podfile = File.read podfile_path
      podfile_content = @pods_for_podfile.map do |pod|
        "pod '" + pod + "'"
      end.join("\n  ")
      podfile.gsub!("${INCLUDED_PODS}", podfile_content)
      File.open(podfile_path, "w") { |file| file.puts podfile }
    end

    def customise_prefix
      prefix_path = "Example/Tests/Tests-Prefix.pch"
      return unless File.exists? prefix_path

      pch = File.read prefix_path
      pch.gsub!("${INCLUDED_PREFIXES}", @prefixes.join("\n  ") )
      File.open(prefix_path, "w") { |file| file.puts pch }
    end

    def run_pod_install
      puts "\nRunning " + "pod install".magenta + " on your new library."
      puts ""

      Dir.chdir("Example") do
        system "pod install"
      end
    end

    def initialize_git_repo
      `git init`
      `git add -A`
      `git commit -m "Initial commit"`
    end

    def finalize_staging_directory
      `rm -rf templates`
    end

    #----------------------------------------#

    def ask(question)
      answer = ""
      loop do
        puts "\n#{question}?"

        @message_bank.show_prompt
        answer = gets.chomp

        break if answer.length > 0

        print "\nYou need to provide an answer."
      end
      answer
    end

    def ask_with_answers(question, possible_answers)

      print "\n#{question}? ["

      print_info = Proc.new {

        possible_answers_string = possible_answers.each_with_index do |answer, i|
           _answer = (i == 0) ? answer.underline : answer
           print " " + _answer
           print(" /") if i != possible_answers.length-1
        end
        print " ]\n"
      }
      print_info.call

      answer = ""

      loop do
        @message_bank.show_prompt
        answer = gets.downcase.chomp

        answer = "yes" if answer == "y"
        answer = "no" if answer == "n"

        # default to first answer
        if answer == ""
          answer = possible_answers[0].downcase
          print answer.yellow
        end

        break if possible_answers.map { |a| a.downcase }.include? answer

        print "\nPossible answers are ["
        print_info.call
      end

      answer
    end

    def add_pod_to_podfile podname
      @pods_for_podfile << podname
    end

    def add_line_to_pch line
      @prefixes << line
    end

    def validate_user_details
        return (user_email.length > 0) && (user_name.length > 0)
    end

  end
end
