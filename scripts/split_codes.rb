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
      # string.gsub(/\{\{\s*([^}]+)\s*,\s*([^}]+)\s*\}\}/, '{{<<\2>>,\1}}')
      string.gsub(/\{\{\s*([^}]+)\s*,\s*([^}]+)\s*\}\}/, '{{<<\2>>}}')
            .gsub(/\(\{\{([^}]+)\}\}\)/, '{{\1}}')
      # we want this to be {{<<\2>>,term}}, once the term is identified in the source YAML: https://github.com/glossarist/iev-document/issues/10
    end

    def fix_image_paths(string)
      string
        .gsub('image::/assets/images/', 'image::')
        .gsub('/60050-', '/')
    end

    def fix_github_issues(string)
      refs_patch(swap_term_refs(fix_image_paths(string)))
    end

    def refs_patch(string)
      string.gsub(/IEC 60050-191:1990/, '<<IEV191_1990>>')
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
      ret = {}
      a = term['usage_info'] and ret['field-of-application'] = a
      a = term['language_code'] and ret['language'] = iso3_to_iso2(a)
      if a = term['gender']
        ret['grammar'] = {} unless ret['grammar']
        ret['grammar']['gender'] = gender(a)
      end
      if (a = term['plurality']) && a != 'singular'
        ret['grammar'] = {} unless ret['grammar']
        ret['grammar']['number'] = a
      end

      return if ret.empty?

      out = "\n\n[%metadata]\n"
      out += ret.keys.reject { |k| k == 'grammar' }.map { |k| "#{k}:: #{ret[k]}" }.join("\n")
      out += "\ngrammar::\n" if ret['grammar']
      out += ret['grammar']&.keys&.map { |k| "#{k}::: #{ret['grammar'][k]}" }&.join("\n") || ''
      out
    end

    def gender(code)
      case code
      when 'm' then 'masculine'
      when 'f' then 'feminine'
      when 'n' then 'neuter'
      end
    end

    def iso3_to_iso2(code)
      case code
      when 'ara' then 'ar'
      when 'ces' then 'cs'
      when 'ger', 'deu' then 'de'
      when 'eng' then 'en'
      when 'fra' then 'fr'
      when 'jpn' then 'jp'
      when 'kor' then 'ko'
      when 'pol' then 'pl'
      when 'por' then 'pt'
      when 'chi', 'zho' then 'zh'
      when 'spa' then 'es'
      else
        "XXX#{code}"
      end
    end

    def process_codes(yaml)
      english = yaml['eng']
      french = yaml['fra']
      otherlangs = []
      yaml.each do |term, val|
        next if %w[termid term eng fra].include? term
        next unless val.is_a?(Hash) && val['terms']

        val['terms'].each do |t|
          next unless t['normative_status'] == 'preferred'
          next unless t['type'] == 'expression'

          t['language_code'] = term
          otherlangs << "preferred:[#{t['designation']}]#{designation_metadata(t)}"
        end
      end
      process_codes1(yaml, english, otherlangs.join("\n\n")) +
        process_codes1(yaml, french, nil)
    end

    def process_codes1(yaml, languageterm, otherlangs)
      return '' if languageterm.nil?

      definition = fix_github_issues(languageterm['definition'])
      source = get_source_string(languageterm['authoritative_source'])
      md = designation_metadata(languageterm['terms'][0])

      # puts languageterm.inspect
      <<~EOF

        [language="#{iso3_to_iso2(languageterm['language_code'])}",tag=#{yaml['termid']}]
        ==== #{languageterm['terms'][0]['designation']}#{md}

        #{
          if languageterm['terms'][1]
            languageterm['terms'][1..-1].map do |term|
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

        #{otherlangs}

        #{definition}

        #{
          languageterm['notes'].map do |note|
            "NOTE: #{fix_github_issues(note)}\n"
          end.join("\n")
        }

        #{
          languageterm['examples'].map do |example|
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
