//
//  StockfishBridge.mm
//  CHESS ENGINE PRO
//
//  In-process UCI transport. Stockfish's main() is renamed to
//  stockfish_main at compile time; we install custom std::cin/std::cout
//  stream buffers so the UCI loop talks to Swift instead of a terminal.
//

#import "StockfishBridge.h"

#include <algorithm>
#include <condition_variable>
#include <cstring>
#include <deque>
#include <iostream>
#include <mutex>
#include <streambuf>
#include <string>
#include <thread>
#include <vector>

extern int stockfish_main(int argc, char **argv);

namespace {

// MARK: - Thread safe line queue

class LineQueue {
public:
    void push(const std::string &line) {
        {
            std::lock_guard<std::mutex> guard(mutex_);
            if (closed_) return;
            pending_.push_back(line);
            // Bounded queue: never let a misbehaving engine grow memory.
            while (pending_.size() > 1024) pending_.pop_front();
        }
        available_.notify_one();
    }

    bool pop(std::string &out, bool blocking) {
        std::unique_lock<std::mutex> lock(mutex_);
        if (blocking) {
            available_.wait(lock, [this] { return closed_ || !pending_.empty(); });
        }
        if (pending_.empty()) return false;
        out = std::move(pending_.front());
        pending_.pop_front();
        return true;
    }

    void close() {
        {
            std::lock_guard<std::mutex> guard(mutex_);
            closed_ = true;
        }
        available_.notify_all();
    }

    void reopen() {
        std::lock_guard<std::mutex> guard(mutex_);
        closed_ = false;
        pending_.clear();
    }

    bool isClosed() {
        std::lock_guard<std::mutex> guard(mutex_);
        return closed_;
    }

private:
    std::mutex mutex_;
    std::condition_variable available_;
    std::deque<std::string> pending_;
    bool closed_ = false;
};

// MARK: - std::cin replacement

class InputBuffer : public std::streambuf {
public:
    explicit InputBuffer(LineQueue &queue) : queue_(queue) {}

protected:
    int_type underflow() override {
        if (position_ < current_.size()) {
            return traits_type::to_int_type(current_[position_]);
        }
        std::string line;
        if (!queue_.pop(line, true)) return traits_type::eof();
        current_ = line;
        current_.push_back('\n');
        position_ = 0;
        return traits_type::to_int_type(current_[0]);
    }

    int_type uflow() override {
        const int_type value = underflow();
        if (!traits_type::eq_int_type(value, traits_type::eof())) {
            position_ += 1;
        }
        return value;
    }

    std::streamsize xsgetn(char *target, std::streamsize count) override {
        std::streamsize written = 0;
        while (written < count) {
            const int_type value = uflow();
            if (traits_type::eq_int_type(value, traits_type::eof())) break;
            target[written] = traits_type::to_char_type(value);
            written += 1;
        }
        return written;
    }

private:
    LineQueue &queue_;
    std::string current_;
    size_t position_ = 0;
};

// MARK: - std::cout replacement

class OutputBuffer : public std::streambuf {
public:
    explicit OutputBuffer(LineQueue &queue) : queue_(queue) {}

protected:
    std::streamsize xsputn(const char *text, std::streamsize count) override {
        for (std::streamsize index = 0; index < count; ++index) {
            append(text[index]);
        }
        return count;
    }

    int_type overflow(int_type character) override {
        if (!traits_type::eq_int_type(character, traits_type::eof())) {
            append(traits_type::to_char_type(character));
        }
        return traits_type::not_eof(character);
    }

    // Stockfish flushes after every insertion (std::ios::unitbuf), so one UCI
    // line such as "bestmove e2e4" arrives as several writes. Only a newline
    // terminates a line here - flushing partial text would split the line and
    // hand the reader a bare "bestmove " without a move.
    int sync() override {
        return 0;
    }

private:
    void append(char character) {
        if (character == '\r') return;
        if (character == '\n') {
            queue_.push(partial_);
            partial_.clear();
            return;
        }
        partial_.push_back(character);
    }

    LineQueue &queue_;
    std::string partial_;
};

// MARK: - Global engine state

struct EngineState {
    LineQueue output;
    LineQueue input;
    InputBuffer inputBuffer{input};
    OutputBuffer outputBuffer{output};
    std::thread worker;

    std::streambuf *savedCin = nullptr;
    std::streambuf *savedCout = nullptr;
    std::streambuf *savedCerr = nullptr;

    bool running = false;
    std::mutex mutex;
};

EngineState &state() {
    static EngineState instance;
    return instance;
}

}  // namespace

extern "C" {

bool sf_available(void) {
    return true;
}

const char *sf_engine_name(void) {
    return "Stockfish";
}

bool sf_start(void) {
    EngineState &engine = state();
    std::lock_guard<std::mutex> guard(engine.mutex);
    if (engine.running) return true;

    engine.input.reopen();
    engine.output.reopen();

    engine.savedCin = std::cin.rdbuf(&engine.inputBuffer);
    engine.savedCout = std::cout.rdbuf(&engine.outputBuffer);
    engine.savedCerr = std::cerr.rdbuf(&engine.outputBuffer);
    std::cout.setf(std::ios::unitbuf);

    engine.running = true;
    engine.worker = std::thread([] {
        EngineState &inner = state();
        static char name[] = "stockfish";
        char *arguments[] = {name, nullptr};
        stockfish_main(1, arguments);
        {
            std::lock_guard<std::mutex> lock(inner.mutex);
            inner.running = false;
        }
        inner.output.close();
    });

    return true;
}

void sf_write(const char *command) {
    if (!command) return;
    state().input.push(std::string(command));
}

int sf_read_line(char *out, int maxLen) {
    if (!out || maxLen < 2) return -1;
    std::string line;
    if (!state().output.pop(line, true)) return -1;
    const size_t usable = std::min<size_t>(line.size(), static_cast<size_t>(maxLen) - 1);
    if (usable > 0) std::memcpy(out, line.data(), usable);
    out[usable] = '\0';
    return static_cast<int>(usable);
}

void sf_shutdown(void) {
    EngineState &engine = state();
    {
        std::lock_guard<std::mutex> guard(engine.mutex);
        if (!engine.running) return;
    }
    engine.input.push(std::string("quit"));
    if (engine.worker.joinable()) engine.worker.join();
}

}  // extern "C"
