#
# Retic - Really Tiny CGI library for ruby
#
# Copyright (C) 2011 Tatsuki Sugiura <sugi@nemui.org>
# Lisence: Ruby's
#

require 'cgi'
require 'erb'

class Retic
  class AbortAction < Exception
    def initialize(new_action, params = {})
      @new_action = new_action
      @params = params
    end
    attr_accessor :new_action, :params
  end
  class RedirectAction < AbortAction; end
  class ForwardAction < AbortAction; end

  VERSION = "0.2.0"

  # Options:
  # * :templatedir => set template directory (default: 'templates')
  # * :charset => charset on content-type header
  def initialize(cgi, opts = {})
    @cgi = cgi 
    @templatedir = opts[:templatedir] || 'templates'   
    @charset = opts[:charset] || 'utf-8'
    @cur_action = nil
    @cur_template = nil
    @cgi_headers = opts[:cgi_headers] || {"Cache-Control" => "no-cache"}
    @action_key = 'action'
    @upload_file_autoread = true
  end
  attr_accessor :cgi, :templatedir, :charset, :cgi_headers

  # action runner.
  def run
    pre_execute
    forward_count = 0
    begin
      @cur_template = @cur_action ||= param(@action_key) || 'index'
      unless respond_to? "do_#{@cur_action}"
        cgi.out(gen_cgi_headers("type" => "text/plain", "status" => "400")) {
          "No action '#{CGI.escapeHTML(@cur_action)}'."
        }
        return
      end
      args = __send__("do_#{@cur_action}") || {}
      @cur_template and render @cur_template, args
    rescue ForwardAction => e
      forward_count += 1
      forward_count > 20 and
        raise "Forward count exceeded. Forward may loop."
      @cur_action = e.new_action
      e.params.each do |k, v|
        @cgi[k.to_s] = [v]
      end
      retry
    rescue RedirectAction => e
      raw_redirect url(e.new_action, e.params)
    end
    post_execute
  end

  def pre_execute
  end

  def post_execute
  end

  def gen_cgi_headers(opts = {})
    Hash[*{
      "charset" => charset, "X-Content-Type-Options" => "nosniff"
    }.update(cgi_headers).update(opts).select{|k, v| v }.flatten]
  end

  # Stub function. You need to override.
  def do_index
    @cur_template = nil
    cgi.out(gen_cgi_headers("type" => "text/plain")) {
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
    cgi.out(gen_cgi_headers) {
      if File.exists? "#{templatedir}/layout.erb.html"
        content = view.include_template name
        view.set_variable :content => content
        view.include_template "layout"
      else
        view.include_template name
      end
    }
  end

  def url(action, query_params = {})
    query = query_params.merge(@action_key => action).map {|k, v| "#{CGI.escape(k.to_s)}=#{CGI.escape(v.to_s)}" }.join(';')
    ret = self_url
    query and ret += "?#{query}"
    ret
  end

  def forward(action, params = {})
    raise ForwardAction.new(action, params)
  end

  def redirect(action, params = {})
    raise RedirectAction.new(action, params)
  end

  def raw_redirect(url)
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
    if @upload_file_autoread
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
    end
    if cgi.params[key].size > 1
      return cgi.params[key]
    else
      return cgi.params[key][0]
    end
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

    def link_to(text, action, query_params = {}, html_attrs = {})
      ret = %Q{<a href="#{@controller.url(action, query_params)}"}
      html_attrs.each do |k, v|
        ret << %Q{ #{CGI.escapeHTML(k.to_s)}="#{CGI.escapeHTML(v.to_s)}"}
      end
      ret << ">#{text}</a>"
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
