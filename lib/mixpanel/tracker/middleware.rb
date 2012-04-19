require 'rack'

module Mixpanel
  class Tracker
    class Middleware
      def initialize(app, mixpanel_token, options={})
        @app = app
        @token = mixpanel_token
        @options = {
          :async => false,
          :insert_js_last => false
        }.merge(options)
        puts "@@@@@@@ @options = #{@options.inspect} @@@@@@@@"
      end

      def call(env)
        @env = env

        @status, @headers, @response = @app.call(env)

        if is_trackable_response?
          update_response!
          update_content_length!
          delete_event_queue!
        end

        [@status, @headers, @response]
      end

      private

      def update_response!
        puts "@@@@@@@@@@ IN UPDATE_RESPONSE @@@@@@@@@@"
        @response.each do |part|
          if is_regular_request? && is_html_response?
            insert_at = part.index(@options[:insert_js_last] ? '</body' : '</head')
            unless insert_at.nil?
              part.insert(insert_at, render_event_tracking_scripts) unless queue.empty?
              part.insert(insert_at, render_mixpanel_scripts) #This will insert the mixpanel initialization code before the queue of tracking events.
            end
          elsif is_ajax_request? && is_html_response?
            part.insert(0, render_event_tracking_scripts) unless queue.empty?
          elsif is_ajax_request? && is_javascript_response?
            part.insert(0, render_event_tracking_scripts(false)) unless queue.empty?
          end
        end
      end

      def update_content_length!
        new_size = 0
        @response.each{|part| new_size += part.bytesize}
        @headers.merge!("Content-Length" => new_size.to_s)
      end

      def is_regular_request?
        !is_ajax_request?
      end

      def is_ajax_request?
        @env.has_key?("HTTP_X_REQUESTED_WITH") && @env["HTTP_X_REQUESTED_WITH"] == "XMLHttpRequest"
      end

      def is_html_response?
        @headers["Content-Type"].include?("text/html") if @headers.has_key?("Content-Type")
      end

      def is_javascript_response?
        @headers["Content-Type"].include?("text/javascript") if @headers.has_key?("Content-Type")
      end

      def is_trackable_response?
        is_html_response? || is_javascript_response?
      end

      def render_mixpanel_scripts
        puts "@@@@@@ IN RENDER_MIXPANEL_SCRIPTS @@@@@@@@"
        if @options[:async]
            <<-EOT
          <script type='text/javascript'>
            (function(d,c){var a,b,g,e;a=d.createElement("script");a.type="text/javascript";a.async=!0;a.src=("https:"===d.location.protocol?"https:":"http:")+'//api.mixpanel.com/site_media/js/api/mixpanel.2.js';b=d.getElementsByTagName("script")[0];b.parentNode.insertBefore(a,b);c._i=[];c.init=function(a,d,f){var b=c;"undefined"!==typeof f?b=c[f]=[]:f="mixpanel";g="disable track track_pageview track_links track_forms register register_once unregister identify name_tag set_config".split(" ");
            for(e=0;e<g.length;e++)(function(a){b[a]=function(){b.push([a].concat(Array.prototype.slice.call(arguments,0)))}})(g[e]);c._i.push([a,d,f])};window.mixpanel=c})(document,[]);
            mixpanel.init("#{@token}");
          </script>
            EOT
        else
          <<-EOT
        <script type='text/javascript'>
          var mp_protocol = (('https:' == document.location.protocol) ? 'https://' : 'http://');
          document.write(unescape('%3Cscript src="' + mp_protocol + 'api.mixpanel.com/site_media/js/api/mixpanel.2.js" type="text/javascript"%3E%3C/script%3E'));
        </script>
        <script type='text/javascript'>
          try {
            var mpmetrics = new MixpanelLib('#{@token}');
          } catch(err) {
            null_fn = function () {};
            var mpmetrics = {
              track: null_fn,  track_funnel: null_fn,  register: null_fn,  register_once: null_fn, register_funnel: null_fn
            };
          }
        </script>
          EOT
        end
      end

      def delete_event_queue!
        @env.delete('mixpanel_events')
      end

      def queue
        return [] if !@env.has_key?('mixpanel_events') || @env['mixpanel_events'].empty?
        @env['mixpanel_events']
      end

      def render_event_tracking_scripts(include_script_tag=true)
        puts "@@@@@ IN RENDER_EVENT_TRACKING_SCRIPTS @@@@@"
        return "" if queue.empty?

        if @options[:async]
          output = queue.map {|type, arguments| %(mixpanel.push(["#{type}", #{arguments.join(', ')}]);) }.join("\n")
          puts "@@@@ OUTPUT = #{output} @@@@@@"
        else
          output = queue.map {|type, arguments| %(mpmetrics.#{type}(#{arguments.join(', ')});) }.join("\n")
        end

        output = "try {#{output}} catch(err) {}"

        include_script_tag ? "<script type='text/javascript'>#{output}</script>" : output
      end
    end
  end
end

