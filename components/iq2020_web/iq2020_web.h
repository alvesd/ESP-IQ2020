#pragma once

#include <cstddef>
#include <cstdint>

#include "esphome/components/web_server_base/web_server_base.h"
#include "esphome/core/component.h"
#include "esphome/core/defines.h"

extern const uint8_t IQ2020_WEB_INDEX_GZ[];

namespace esphome {
namespace iq2020_web {

/// Serves the self-contained gzipped IQ2020 Spa web UI on "/" and "/index.html"
/// while leaving ESPHome's "/events" SSE stream and REST entity endpoints to web_server.
class IQ2020WebHandler : public Component, public AsyncWebHandler {
 public:
  IQ2020WebHandler(web_server_base::WebServerBase *base, const uint8_t *html_gz, size_t html_gz_size)
      : base_(base), html_gz_(html_gz), html_gz_size_(html_gz_size) {}

  /// Register before WebServer (WIFI - 1.0f) so GET "/" hits this handler first.
  float get_setup_priority() const override { return setup_priority::WIFI; }

  void setup() override {
    this->base_->init();
    this->base_->add_handler(this);
  }

  bool canHandle(AsyncWebServerRequest *request) const override {
    if (request->method() != HTTP_GET) {
      return false;
    }
#ifdef USE_ESP32
    char url_buf[AsyncWebServerRequest::URL_BUF_SIZE];
    StringRef url = request->url_to(url_buf);
    return url == "/" || url == "/index.html";
#else
    const auto &url = request->url();
    return url == "/" || url == "/index.html";
#endif
  }

  void handleRequest(AsyncWebServerRequest *request) override {
    AsyncWebServerResponse *response =
        request->beginResponse(200, "text/html; charset=utf-8", this->html_gz_, this->html_gz_size_);
    response->addHeader("Content-Encoding", "gzip");
    response->addHeader("Cache-Control", "no-cache");
    request->send(response);
  }

 protected:
  web_server_base::WebServerBase *base_;
  const uint8_t *html_gz_;
  size_t html_gz_size_;
};

}  // namespace iq2020_web
}  // namespace esphome
