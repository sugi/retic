#
# Retic - Really Tiny CGI library for ruby
#
# Copyright (C) 2011 Tatsuki Sugiura <sugi@nemui.org>
# Lisence: Ruby's
#

require 'cgi'
require 'erb'

class Retic
  VERSION = "0.1.0"

  # Options:
  # * :templatedir => set template directory (default: 'templates')
  # * :charset => charset on content-type header
  def initialize(cgi, opts = {})
    @cgi = cgi 
    @templatedir = opts[:templatedir] || 'templates'   
    @charset = opts[:charset] || 'utf-8'
    @cur_action = nil
    @cur_template = nil
  end
  attr_accessor :cgi, :templatedir, :charset

  # action runner.
  def run
    @cur_template = @cur_action ||= param('action') || 'index'
    unless respond_to? "do_#{@cur_action}"
      cgi.out("type" => "text/plain", "charset" => @charset,
	      "status" => "400", "X-Content-Type-Options" => "nosniff") {
	"No action '#{CGI.escapeHTML(@cur_action)}'."
      }
      return
    end
    args = __send__("do_#{@cur_action}") || {}
    @cur_template and render @cur_template, args
  end

  # Stub function. You need to override.
  def do_index
    @cur_template = nil
    cgi.out("type" => "text/plain", "charset" => @charset) {
      <<-"EOT"
      Welcome to Retic! This is stub action for '#{@cur_action}'.
      Put your template file as '#{@templatedir}/#{@cur_action}.erb.html'.
      And define your do_#{@cur_action} to return variables for the template.
      EOT
    }
  end

  def default_vars
    {
      :cgi => cgi,
      :self_url => self_url,
      :controller => self,
    }
  end

  def render(name, user_vars = {})
    view = View.new
    vars = default_vars
    view.set_variable(vars.merge(user_vars))
    cgi.out("charset" => @charset) {
      view.include_template name
    }
  end

  def redirect(url)
    @cur_template = nil
    cgi.print cgi.header({"Location" => url})
  end

  def read_template(name) # :nodoc:
    tmpl = ""
    open("#{templatedir}/#{name}.erb.html") { |t|
      tmpl << t.read
    }
    tmpl
  end

  def self_url
    schema = ENV["HTTPS"] ? "https" : "http"
    "#{schema}://#{ENV["HTTP_HOST"]}#{ENV["SCRIPT_NAME"]}"
  end

  # chortcut for cgi.params (no array support currently)
  def param(key)
    cgi.params[key] or return nil
    begin 
      StringIO === cgi.params[key][0] and 
        return cgi.params[key][0].read
    rescue NameError
      # ignore
    end
    begin
    Tempfile === cgi.params[key][0] and 
        return cgi.params[key][0].read
    rescue NameError
      # ignore
    end
    return cgi.params[key][0]
  end

  # Utility functions and binding on template.
  class View
    # shortcut for CGI.escapeHTML
    def h(str)
      CGI.escapeHTML(str.to_s)
    end

    def set_variable(vars) # :nodoc:
      vars.each { |k, v|
        instance_variable_set("@"+k.to_s, v)
      }
    end

    def get_binding # :nodoc:
      binding
    end

    # include another template
    def include_template(name)
      unless self.respond_to? "_tmpl_#{name}"
        ERB.new(@controller.read_template(name)).def_method(self.class, "_tmpl_#{
name}", "#{name}.erb.html")
      end
      self.__send__ "_tmpl_#{name}"
    end
  end # View

  # CGI class runner with fatal error catcher
  def self.run(cgi = nil)
    cgi ||= CGI.new
    begin
      app = self.new(cgi)
      app.run
    rescue => e
      cgi.out("type" => "text/plain", "charset" => "utf-8",
	      "status" => "500", "X-Content-Type-Options" => "nosniff") {
	["Fatal Error:", e.inspect, "",
	 "Backtrace:", *e.backtrace].join("\n")
      }
    end
  end
end
