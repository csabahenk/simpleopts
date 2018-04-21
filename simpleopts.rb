require 'optparse'


module SimpleOpts

  class Opt

    def self.classfixer c
      (Class === c and c.name == "Fixnum") ? Integer : c
    end

    def self.represent v
      case v
      when ""
        '""'
      when String
        w = v.inspect
        [v, w[1...-1], v.strip].uniq.size == 1 ? v : w
      when Regexp
        v.inspect
      when Class
        ""
      else
        v.to_s
      end
    end

    def initialize name: nil, type: nil, default: :auto, default_rep: nil,
                   short: :auto, argument: :auto, info: "%{default}"
      @name = name
      @default = default
      @type = self.class.classfixer(type ||
                (@default == :auto ? String : @default.class))
      @default_rep = default_rep || self.class.represent(self.default)
      @info = info
      @short = short
      @argument = argument
    end

    attr_accessor :name, :type, :info, :default_rep
    attr_writer :default, :short, :argument

    def default
      @default == :auto ? type : @default
    end

    def argument
      @argument == :auto or return @argument

      # Classes don't match themselves with === operator,
      # so the case construct has to dispatch on their names.
      # Also some of the classes we are to dispatch on may
      # not be defined (Date*) -- thus dispatching on the name
      # avoids reference to an undefined.
      case type.name
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
    end

    def short
      case @short
      when :auto, true
        @name[0]
      when nil, false
        nil
      else
        @short
      end
    end

    def short_set?
      @short != :auto
    end

  end

  def self.get inopts, config_file_opt: nil, keep_config_file: false, argv: $*,
      optclass: Opt, missing_cbk: nil
    opts = {}
    [inopts].flatten.each { |oh|
      opts.merge! oh.map { |o,d|
        optname = o.to_s.gsub "_", "-"
        opt = case d
        when Opt,optclass
          d.name ||= optname
          d
        when Class
          optclass.new name: optname, type: d
        else
          optclass.new name: optname, default: d
        end
        [o, {opt: opt, default: opt.default}]
      }.to_h
    }
    shortopts = []
    OptionParser.new { |op|
      opts.each { |o,w|
        # Mangling opts to OptionParser options in a graceful manner
        # - opt_name: <scalar> becomes:
        #   op.on("-o", "--opt-name", fixer[<scalar>.class], <scalar>.to_s) {...}
        # - opt_name: <class> becomes: op.on("-o", "--opt-name", fixer[<class>]) {...}
        #   where fixer is needed to map arbitrary classes into the class set
        #   accepted by OptionParser
        # This is actually the special case of the following general mechanism
        # (through making an Opt instance <opt> from given <scalar>/<class>):
        # - opt_name: <opt> becomes:
        #   op.on("-"+<opt>.short, "--" + <opt>.name, <opt>.type,
        #         <opt>.info % <opt>.default) {...}
        opt = w[:opt]
        if shortopts.include? opt.short
          opt.short_set? or opt.short = nil
        else
          shortopts << opt.short
        end
        optargs = [
          opt.short ? "-" + opt.short : nil,
          ["--" + opt.name, opt.argument].compact.join("="),
          opt.type,
          opt.info % {default: opt.default_rep}
        ].compact
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
        optname = w[:opt].name
        if missing_cbk
          missing_cbk[optname]
        else
          puts "missing value for --#{optname}"
          exit 1
        end
      end
      opts[o] = v
    }

    opts
  end

end
