module Tools
  class SalaryBookSseController < ApplicationController
    include ActionController::Live

    # GET /tools/salary-book/sse/demo
    #
    # Proves:
    # - Rails ActionController::Live streaming
    # - Datastar SSE event framing (patch-signals + patch-elements)
    def demo
      response.headers["Content-Type"] = "text/event-stream; charset=utf-8"
      response.headers["Cache-Control"] = "no-cache, no-transform"
      response.headers["X-Accel-Buffering"] = "no" # nginx
      response.headers["Last-Modified"] = Time.now.httpdate
      response.headers.delete("ETag")

      sse = ActionController::Live::SSE.new(response.stream, retry: 5_000)

      begin
        write_signals(sse, ssestatus: "connected", sseticks: 0)
        write_flash(sse, "SSE connected (streaming 5 ticks)…")

        1.upto(5) do |i|
          sleep 0.6
          write_signals(sse, ssestatus: "streaming", sseticks: i)
          append_log(sse, "tick #{i} @ #{Time.now.strftime('%H:%M:%S')}")
        end

        write_signals(sse, ssestatus: "done")
        write_flash(sse, "SSE done.")
      rescue ActionController::Live::ClientDisconnected
        # client navigated away / closed tab
      ensure
        sse.close
      end
    end

    private

    def write_signals(sse, **signals)
      sse.write("signals #{signals.to_json}", event: "datastar-patch-signals")
    end

    def write_flash(sse, message)
      html = "<div id=\"flash\">#{ERB::Util.h(message)}</div>"
      sse.write(datastar_elements_by_id_payload(html), event: "datastar-patch-elements")
    end

    def append_log(sse, message)
      html = "<div class=\"sse-log-line\">#{ERB::Util.h(message)}</div>"
      sse.write(
        datastar_elements_payload(selector: "#sse-log", html:, mode: "append"),
        event: "datastar-patch-elements",
      )
    end

    def datastar_elements_payload(selector:, html:, mode: "inner")
      [
        "mode #{mode}",
        "selector #{selector}",
        *html.lines.map { |l| "elements #{l.chomp}" },
      ].join("\n")
    end

    # Morph-by-id payload (no selector/mode; Datastar matches on top-level `id` attributes).
    def datastar_elements_by_id_payload(html)
      html.lines.map { |l| "elements #{l.chomp}" }.join("\n")
    end
  end
end
