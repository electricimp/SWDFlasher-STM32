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

const LOG_DEBUG_LEVEL       = 2;
const LOG_INFO_LEVEL        = 1;
const LOG_ERROR_LEVEL       = 0;
const LOG_NO_LOGGING_LEVEL  = -1;

enum LOG_SOURCE {
    // Common sources
    ANY             = 0xFFFF,
    APP             = 0x0001,

    // Device sources
    SWDP            = 0x0002,
    SWMA            = 0x0004,
    SWDSTM32        = 0x0008,

    // Agent sources
}

// This class is used for logging
class Logger {

    _uart = null;
    _level = null;
    _sources = null;

    static _names = {
        [LOG_SOURCE.APP]                = "App",
        [LOG_SOURCE.SWDP]               = "SWDebugPort",
        [LOG_SOURCE.SWMA]               = "SWMemAP",
        [LOG_SOURCE.SWDSTM32]           = "SWDSTM32"
    };

    constructor(level = LOG_DEBUG_LEVEL, sources = LOG_SOURCE.ANY, uart = null) {
        if (uart) {
            _uart = uart;
            _uart.configure(19200, 8, PARITY_NONE, 1, NO_CTSRTS);
        }

        _level = level;
        _sources = sources;
    }

    function debug(text, source = LOG_SOURCE.ANY) {
        (_level >= LOG_DEBUG_LEVEL) && _log(text, source);
    }

    function info(text, source = LOG_SOURCE.ANY) {
        (_level >= LOG_INFO_LEVEL) && _log(text, source);
    }

    function error(text, source = LOG_SOURCE.ANY) {
        (_level >= LOG_ERROR_LEVEL) && _logError(text, source);
    }

    function _log(text, source) {
        if (_sources & source) {
            if (source != LOG_SOURCE.ANY && source in _names) {
                text = "[" + _names[source] + "] " + text;
            }
            // NOTE: In case of usage of SUSPEND_ON_ERROR timeout policy, it is necessary
            // to add a check of the current device's connectivity state
            server.log(text);

            // send the string to uart if it's enabled
            _uart && _uart.write(text + "\n\r");
        }
    }

    function _logError(text, source) {
        if (_sources & source) {
            if (source != LOG_SOURCE.ANY && source in _names) {
                text = "[" + _names[source] + "] " + text;
            }
            // NOTE: In case of usage of SUSPEND_ON_ERROR timeout policy, it is necessary
            // to add a check of the current device's connectivity state
            server.error(text);

            // send the string to uart if it's enabled
            _uart && _uart.write(text + "\n\r");
        }
    }
}