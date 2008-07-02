# $Id$

# Equivalent to a header guard in C/C++
# Used to prevent the class/module from being loaded more than once
unless defined? Logging

# TODO: internal logger for debugging
# TODO: Windows Log Service appender

#
#
module Logging

  # :stopdoc:
  VERSION = '0.8.0'
  LIBPATH = ::File.expand_path(::File.dirname(__FILE__)) + ::File::SEPARATOR
  PATH = ::File.dirname(LIBPATH) + ::File::SEPARATOR
  WIN32 = %r/djgpp|(cyg|ms|bcc)win|mingw/ =~ RUBY_PLATFORM
  LEVELS = {}
  LNAMES = {}
  # :startdoc:

  class << self

    # call-seq:
    #    Logging.configure( filename )
    #
    # Configures the Logging framework using the configuration information
    # found in the given file. The file extension should be either '.yaml'
    # or '.yml' (XML configuration is not yet supported).
    #
    def configure( filename, *args )
      case File.extname(filename)
      when '.yaml', '.yml'
        ::Logging::Config::YamlConfigurator.load(filename, *args)
      else raise ArgumentError, 'unknown configuration file format' end
    end

    # call-seq:
    #    Logging.logger( device, age = 7, size = 1048576 )
    #    Logging.logger( device, age = 'weekly' )
    #
    # This convenience method returns a Logger instance configured to behave
    # similarly to a core Ruby Logger instance.
    #
    # The _device_ is the logging destination. This can be a filename
    # (String) or an IO object (STDERR, STDOUT, an open File, etc.). The
    # _age_ is the number of old log files to keep or the frequency of
    # rotation (+daily+, +weekly+, or +monthly+). The _size_ is the maximum
    # logfile size and is only used when _age_ is a number.
    #
    # Using the same _device_ twice will result in the same Logger instance
    # being returned. For example, if a Logger is created using STDOUT then
    # the same Logger instance will be returned the next time STDOUT is
    # used. A new Logger instance can be obtained by closing the previous
    # logger instance.
    #
    #    log1 = Logging.logger(STDOUT)
    #    log2 = Logging.logger(STDOUT)
    #    log1.object_id == log2.object_id  #=> true
    #
    #    log1.close
    #    log2 = Logging.logger(STDOUT)
    #    log1.object_id == log2.object_id  #=> false
    #
    # The format of the log messages can be changed using a few optional
    # parameters. The <tt>:pattern</tt> can be used to change the log
    # message format. The <tt>:date_pattern</tt> can be used to change how
    # timestamps are formatted. 
    #
    #    log = Logging.logger(STDOUT,
    #              :pattern => "[%d] %-5l : %m\n",
    #              :date_pattern => "%Y-%m-%d %H:%M:%S.%s")
    #
    # See the documentation for the Logging::Layouts::Pattern class for a
    # full description of the :pattern and :date_pattern formatting strings.
    #
    def logger( *args )
      opts = args.pop if args.last.instance_of?(Hash)
      opts ||= Hash.new

      dev = args.shift
      keep = age = args.shift
      size = args.shift

      name = case dev
             when String; dev
             when File; dev.path
             else dev.object_id.to_s end

      repo = ::Logging::Repository.instance
      return repo[name] if repo.has_logger? name

      l_opts = {
        :pattern => "%.1l, [%d #%p] %#{::Logging::MAX_LEVEL_LENGTH}l : %m\n",
        :date_pattern => '%Y-%m-%dT%H:%M:%S.%s'
      }
      [:pattern, :date_pattern, :date_method].each do |o|
        l_opts[o] = opts.delete(o) if opts.has_key? o
      end
      layout = ::Logging::Layouts::Pattern.new(l_opts)

      a_opts = Hash.new
      a_opts[:size] = size if size.instance_of?(Fixnum)
      a_opts[:age]  = age  if age.instance_of?(String)
      a_opts[:keep] = keep if keep.instance_of?(Fixnum)
      a_opts[:filename] = dev if dev.instance_of?(String)
      a_opts[:layout] = layout
      a_opts.merge! opts

      appender =
          case dev
          when String
            ::Logging::Appenders::RollingFile.new(name, a_opts)
          else 
            ::Logging::Appenders::IO.new(name, dev, a_opts)
          end

      logger = ::Logging::Logger.new(name)
      logger.add_appenders appender
      logger.additive = false

      class << logger
        def close
          @appenders.each {|a| a.close}
          h = ::Logging::Repository.instance.instance_variable_get :@h
          h.delete(@name)
          class << self; undef :close; end
        end
      end

      logger
    end

    # call-seq:
    #    Logging.init( levels )
    #
    # Defines the levels available to the loggers. The _levels_ is an array
    # of strings and symbols. Each element in the array is downcased and
    # converted to a symbol; these symbols are used to create the logging
    # methods in the loggers.
    #
    # The first element in the array is the lowest logging level. Setting the
    # logging level to this value will enable all log messages. The last
    # element in the array is the highest logging level. Setting the logging
    # level to this value will disable all log messages except this highest
    # level.
    #
    # This method should only be invoked once to configure the logging
    # levels. It is automatically invoked with the default logging levels
    # when the first logger is created.
    #
    # The levels "all" and "off" are reserved and will be ignored if passed
    # to this method.
    #
    # Example:
    #
    #    Logging.init :debug, :info, :warn, :error, :fatal
    #    log = Logging::Logger['my logger']
    #    log.level = :warn
    #    log.warn 'Danger! Danger! Will Robinson'
    #    log.info 'Just FYI'                        # => not logged
    #
    # or
    #
    #    Logging.init %w(DEBUG INFO NOTICE WARNING ERR CRIT ALERT EMERG)
    #    log = Logging::Logger['syslog']
    #    log.level = :notice
    #    log.warning 'This is your first warning'
    #    log.info 'Just FYI'                        # => not logged
    #
    def init( *args )
      args = %w(debug info warn error fatal) if args.empty?

      args.flatten!
      levels = ::Logging::LEVELS.clear
      names = ::Logging::LNAMES.clear

      id = 0
      args.each do |lvl|
        lvl = levelify lvl
        unless levels.has_key?(lvl) or lvl == 'all' or lvl == 'off'
          levels[lvl] = id 
          names[id] = lvl.upcase
          id += 1
        end
      end

      longest = names.values.inject {|x,y| (x.length > y.length) ? x : y}
      module_eval "MAX_LEVEL_LENGTH = #{longest.length}"

      levels.keys
    end
   
    # call-seq:
    #    Logging.format_as( obj_format )
    #
    # Defines the default _obj_format_ method to use when converting objects
    # into string representations for logging. _obj_format_ can be one of
    # <tt>:string</tt>, <tt>:inspect</tt>, or <tt>:yaml</tt>. These
    # formatting commands map to the following object methods
    #
    # * :string  => to_s
    # * :inspect => inspect
    # * :yaml    => to_yaml
    #
    # An +ArgumentError+ is raised if anything other than +:string+,
    # +:inspect+, +:yaml+ is passed to this method.
    #
    def format_as( f )
      f = f.intern if f.instance_of? String

      unless [:string, :inspect, :yaml].include? f
        raise ArgumentError, "unknown object format '#{f}'"
      end

      module_eval "OBJ_FORMAT = :#{f}"
    end

    # Returns the version string for the library.
    #
    def version
      VERSION
    end

    # Returns the library path for the module. If any arguments are given,
    # they will be joined to the end of the libray path using
    # <tt>File.join</tt>.
    #
    def libpath( *args )
      args.empty? ? LIBPATH : ::File.join(LIBPATH, *args)
    end

    # Returns the lpath for the module. If any arguments are given,
    # they will be joined to the end of the path using
    # <tt>File.join</tt>.
    #
    def path( *args )
      args.empty? ? PATH : ::File.join(PATH, *args)
    end

    # Utility method used to rquire all files ending in .rb that lie in the
    # directory below this file that has the same name as the filename passed
    # in. Optionally, a specific _directory_ name can be passed in such that
    # the _filename_ does not have to be equivalent to the directory.
    #
    def require_all_libs_relative_to( fname, dir = nil )
      dir ||= ::File.basename(fname, '.*')
      search_me = ::File.expand_path(
          ::File.join(::File.dirname(fname), dir, '*.rb'))

      Dir.glob(search_me).sort.each {|rb| require rb}
    end

    # :stopdoc:
    # Convert the given level into a connaconical form - a lowercase string.
    def levelify( level )
      case level
      when String; level.downcase
      when Symbol; level.to_s.downcase
      else raise ArgumentError, "levels must be a String or Symbol" end
    end

    # Convert the given level into a level number.
    def level_num( level )
      l = levelify level
      case l
      when 'all'; 0
      when 'off'; LEVELS.length
      else begin; Integer(l); rescue ArgumentError; LEVELS[l] end end
    end
    # :startdoc:
  end
end  # module Logging

Logging.require_all_libs_relative_to(__FILE__)
Logging.require_all_libs_relative_to(__FILE__, 'logging/config')

# This exit handler will close all the appenders that exist in the system.
# This is needed for closing IO streams and connections to the syslog server
# or e-mail servers, etc.
#
at_exit {
  Logging::Appender.instance_variable_get(:@appenders).values.each do |ap|
    ap.close
  end
}

end  # unless defined?

# EOF
