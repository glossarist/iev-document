#!/usr/bin/env ruby
# frozen_string_literal: true

require 'fileutils'
require 'yaml'

class SplitCodes
  class << self
    def split(input, output)
      output_dir = File.dirname(output)
      ensure_dir(output_dir)
      yaml = YAML.load(IO.read(input))
      # puts yaml.inspect

      adoc = process_codes(yaml)
      File.open(output, 'w') do |f|
        f.puts adoc
      end
    end

    def process_codes(yaml)
      english = yaml["eng"]

      # puts english.inspect
      <<~EOF

        ==== #{english["terms"][0]["designation"]}

        #{
          if english["terms"][1]
            english["terms"][1..-1].map do |term|

              des = term["designation"]
              case term["type"]
              when "symbol"
                des = "stem:[#{des}]"
              end

              case term["normativeStatus"]
              when "admitted", "preferred"
                "alt:[#{term["designation"]}] #{term["usageInfo"] ? "<#{term["usageInfo"]}>" : ""}"
              when "deprecated"
                "deprecated:[#{term["designation"]}] #{term["usageInfo"] ? "<#{term["usageInfo"]}>" : ""}"
              end
            end.join("\n")
          end
        }

        #{english["definition"]}

        #{
          english["notes"].map do |note|
            "NOTE: #{note}\n"
          end.join("\n")
        }

        #{
          english["examples"].map do |example|
            "[example]\n--\n#{example}\n--\n"
          end.join("\n")
        }

        #{
        if english["authoritative_source"]
          string = "[.source]\n"
          string = string + english["authoritative_source"]["ref"]
          string = string + ", " + english["authoritative_source"]["clause"] if english["authoritative_source"]["clause"]
          string
        end
        }

      EOF
    end

    def ensure_dir(dir)
      FileUtils.mkdir_p(dir)
    end
  end
end

def show_usage
  puts "Usage:  #{$PROGRAM_NAME}  INPUT_YAML_FILE  OUTPUT_ADOC_FILE"
end

def main
  if ARGV.length != 2
    show_usage
    exit 1
  end

  input = ARGV[0]
  output_dir = ARGV[1]
  SplitCodes.split(input, output_dir)
end

main if $PROGRAM_NAME == __FILE__

__END__
