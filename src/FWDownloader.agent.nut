// MIT License

// Copyright 2019 Electric Imp

// SPDX-License-Identifier: MIT

// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:

// The above copyright notice and this permission notice shall be
// included in all copies or substantial portions of the Software.

// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
// EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO
// EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES
// OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
// ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
// OTHER DEALINGS IN THE SOFTWARE.

const FW_HTTP_D_ERROR_NO_MORE_DATA = 1;

class FirmwareHTTPDownloader {

    _url = null;
    _headers = null;
    _chunkSize = null;
    _fw = null;

    constructor(url, headers = {}, chunkSize = 4096) {
        const FW_HTTP_D_MAX_REDIRECTIONS = 3;

        _url = url;
        _chunkSize = chunkSize;

        if (headers != null) {
            _headers = headers;
        }
    }

    function init(callback) {
        local req = http.get(_url, _headers);

        local redirections = 0;

        local onSent = null;
        onSent = function(res) {
            if (res.statuscode == 301 || res.statuscode == 302) {
                // Redirection
                if ("location" in res.headers && redirections < FW_HTTP_D_MAX_REDIRECTIONS) {

                    redirections++;

                    req = http.get(res.headers.location, _headers);
                    req.sendasync(onSent);

                } else {
                    callback(res.statuscode);
                }

                return;

            } else if (res.statuscode / 100 != 2) {

                callback(res.statuscode);
                return;
            }

            _fw = blob();
            _fw.writestring(res.body);
            callback(0);

        }.bindenv(this);

        req.sendasync(onSent);
    }

    function getChunk(num, callback) {
        if (_fw == null || (num * _chunkSize) >= _fw.len()) {
            callback(FW_HTTP_D_ERROR_NO_MORE_DATA, null);
            return;
        }

        _fw.seek(num * _chunkSize);

        callback(0, _fw.readblob(_chunkSize));
    }

    function chunksNum() {
        if (_fw == null) {
            return 0;
        }
        return (_fw.len() + _chunkSize - 1)  / _chunkSize;
    }
}