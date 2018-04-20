require 'optparse'


######################################################################################


module SimpleOpts

  def self.represent v
    case v
    when ""
      '""'
    when String
      w = v.inspect
      [v, w[1...-1], v.strip].uniq.size == 1 ? v : w
    when Regexp
      v.inspect
    else
      v.to_s
    end
  end

  def self.get inopts, config_file_opt: nil, keep_config_file: false, argv: $*,
      missing_cbk: nil
    opts = {}
    [inopts].flatten.each { |oh|
      opts.merge! oh.map { |o,d| [o, {default: d}] }.to_h
    }
    fixer = proc { |c| (Class === c and c.name == "Fixnum") ? Integer : c }
    shortopts = []
    OptionParser.new { |op|
       opts.each { |o,w|
         # Mangling opts to OptionParser options in a disgraced manner
         # - opt_name: <scalar> becomes:
         #   op.on("-o", "--opt-name", fixer[<scalar>.class], <scalar>.to_s) {...}
         # - opt_name: <class> becomes: op.on("-o", "--opt-name", fixer[<class>]) {...}
         #   where fixer is needed to map arbitrary classes into the class set
         #   accepted by OptionParser
         defval = w[:default]
         optclass = fixer.call case defval
         when Class
           defval
         when nil
           String
         else
           defval.class
         end
         # Classes don't match themselves with === operator,
         # so the case construct has to dispatch on their names.
         # Also some of the classes we are to dispatch on may
         # not be defined (Date*) -- thus dispatching on the name
         # avoids reference to an undefined.
         valrep = case optclass.name
         when 'Integer','Float'
           "N"
         when 'TrueClass','FalseClass'
           "[BOOL]"
         when 'Array'
           "VAL,.."
         when 'Regexp'
           "PAT"
         when 'Date','Time','DateTime'
           "T"
         else
           "VAL"
         end
         shortie = "-#{o[0]}"
         optargs = [
          shortopts.include?(shortie) ? [] : (shortopts << shortie; [shortie]),
          "--#{o.to_s.gsub "_", "-"}=#{valrep}",
          [optclass] + (Class === defval ? [] : [represent(defval)])
         ].flatten
         op.on(*optargs) { |v| opts[o][:cmdline] = v }
       }
    }.parse! argv
    if config_file_opt
      config_file = (opts[config_file_opt]||{}).values_at(
         :cmdline, :default).compact.first
      keep_config_file or opts.delete(config_file_opt)
      if config_file
        YAML.load_file(config_file).each { |k,v|
          (opts[k.to_sym]||{})[:conf] = v
        }
      end
    end
    opts.each { |o,w|
      k = %i[cmdline conf default].find { |k| w.key? k }
      v = w[k]
      if Class === v
        if missing_cbk
          missing_cbk[o]
        else
          puts "missing value for --#{o}"
          exit 1
        end
      end
      opts[o] = v
    }

    opts
  end

end
