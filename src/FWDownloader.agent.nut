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