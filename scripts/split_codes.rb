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

    def swap_term_refs(string)
      string.gsub(/\{\{\s*([^}]+)\s*,\s*([^}]+)\s*\}\}/, '{{<<\2>>,\1}}')
    end

    def fix_image_paths(string)
      string
        .gsub('image::/assets/images/', 'image::')
        .gsub('/60050-', '/')
    end

    def fix_github_issues(string)
      swap_term_refs(fix_image_paths(string))
    end

    def get_source_string(termyaml)
      return unless termyaml
      return unless termyaml.first

      source_data = termyaml.first
      source_data['ref']&.sub!(/IEC\u00A0/, 'IEC ')
      source_data['ref']&.sub!(/ISO\u00A0/, 'ISO ')
      source_data['ref']&.sub!(%r{ISO/IEC/IEEE\u00A0}, 'ISO/IEC/IEEE ')
      source_data['clause']&.sub!(%r{^<i>Systems and software engineering – Vocabulary</i>, }, '')

      source_string = "[.source]\n"

      # TODO: Problem here is that the `ref`s cannot be added to the bibliography
      # e.g. in 192-01-17, the source is ISO 9000.
      # but we can't add a proper reference here unless we have that in the
      # bibliography.
      if source_data['ref'].match(/^IEC 60050/) && !source_data['clause'].nil?
        source_string += "<<IEV,clause \"#{source_data['clause']}\">>"
      elsif source_data['ref'].match(/^ISO 9000/) && !source_data['clause'].nil?
        source_string += "<<ISO9000,clause \"#{source_data['clause']}\">>"
      elsif source_data['ref'].match(%r{^ISO/IEC 2382-1:1993}) && !source_data['clause'].nil?
        source_string += "<<ISOIEC2382-1,clause \"#{source_data['clause']}\">>"
      elsif source_data['ref'].match(%r{^ISO/IEC/IEEE 24765:2010}) && !source_data['clause'].nil?
        source_string += "<<ISO24765,clause \"#{source_data['clause']}\">>"
      else
        source_string += source_data['ref']
        source_string += ", #{source_data['clause']}" if source_data['clause']
      end

      if source_data['relationship'] && (source_data['relationship']['type'] == 'modified')
        source_string += ", #{source_data['relationship']['modification']}"
      end
      source_string
    end

    def designation_metadata(term)
      return '' unless term['usage_info']

      <<~EOF

        [%metadata]
        fieldofapplication:: #{term['usage_info']}
      EOF
    end

    def process_codes(yaml)
      english = yaml['eng']

      definition = fix_github_issues(english['definition'])
      source = get_source_string(english['authoritative_source'])
      md = designation_metadata(english['terms'][0])

      # puts english.inspect
      <<~EOF

        ==== #{english['terms'][0]['designation']}#{md}

        #{
          if english['terms'][1]
            english['terms'][1..-1].map do |term|
              des = term['designation']
              case term['type']
              when 'symbol'
                des = "stem:[#{des}]"
              end

              md = designation_metadata(term)
              case term['normativeStatus']
              when 'admitted', 'preferred'
                "alt:[#{term['designation']}]#{md}"
              when 'deprecated'
                "deprecated:[#{term['designation']}]#{md}"
              end
            end.join("\n")
          end
        }

        #{definition}

        #{
          english['notes'].map do |note|
            "NOTE: #{fix_github_issues(note)}\n"
          end.join("\n")
        }

        #{
          english['examples'].map do |example|
            "[example]\n--\n#{fix_github_issues(example)}\n--\n"
          end.join("\n")
        }

        #{source}

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
