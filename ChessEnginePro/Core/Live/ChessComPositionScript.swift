//
//  ChessComPositionScript.swift
//  CHESS ENGINE PRO
//
//  JavaScript probe injected into the Chess.com page. It only reads what the
//  page already renders for the user:
//
//  * the piece elements of the board (classes and positions),
//  * the visible move list,
//  * the turn indicator of the clocks,
//  * the game over banner.
//
//  Nothing is written back, no cookie is touched and no network request is made
//  from the page. The probe posts a compact payload to the native side whenever
//  the fingerprint of the position changes.
//

import Foundation

enum ChessComPositionScript {

    static let handlerName = "chesscomPosition"

    static let source: String = """
    (function () {
      if (window.__cepLive && window.__cepLive.version >= 4) { return; }

      var HANDLER = "chesscomPosition";
      var PIECES = ["wp", "wn", "wb", "wr", "wq", "wk", "bp", "bn", "bb", "br", "bq", "bk"];
      var session = String(Date.now()) + "-" + String(Math.floor(Math.random() * 1000000));
      var sequence = 0;
      var lastFingerprint = "";
      var debounceTimer = null;

      function boardElement() {
        return document.querySelector("chess-board.board") ||
               document.querySelector("wc-chess-board") ||
               document.querySelector("chess-board") ||
               document.querySelector(".board") ||
               document.querySelector("#board-single") ||
               document.querySelector("[class*='board-layout-chessboard']");
      }

      function isFlipped(board) {
        if (!board) { return false; }
        if ((board.className || "").indexOf("flipped") >= 0) { return true; }
        return !!board.closest(".flipped");
      }

      function pieceToken(el) {
        var list = el.classList;
        for (var i = 0; i < list.length; i++) {
          if (PIECES.indexOf(list[i]) >= 0) { return list[i]; }
        }
        return "";
      }

      function squareFromClass(el) {
        var list = el.classList;
        for (var i = 0; i < list.length; i++) {
          var value = list[i];
          if (value.indexOf("square-") === 0 && value.length === 9) {
            var file = parseInt(value.charAt(7), 10) - 1;
            var rank = parseInt(value.charAt(8), 10) - 1;
            if (file >= 0 && file < 8 && rank >= 0 && rank < 8) {
              return { file: file, rank: rank };
            }
          }
        }
        return null;
      }

      function readBoard() {
        var board = boardElement();
        if (!board) { return null; }
        var flipped = isFlipped(board);
        var nodes = board.querySelectorAll(".piece");
        if (!nodes || nodes.length < 2) { return null; }

        // Mini boards and thumbnails are ignored: a board that small cannot be
        // read reliably and must never produce a guessed position.
        var rect = board.getBoundingClientRect();
        if (rect.width < 200 || rect.height < 200) { return null; }
        var grid = [];
        var i;
        for (i = 0; i < 64; i++) { grid.push("."); }
        var placed = 0;

        for (i = 0; i < nodes.length; i++) {
          var el = nodes[i];
          var token = pieceToken(el);
          if (!token) { continue; }
          var target = squareFromClass(el);
          if (!target && rect.width > 0) {
            var box = el.getBoundingClientRect();
            var col = Math.floor(((box.left + box.width / 2) - rect.left) / (rect.width / 8));
            var row = Math.floor(((box.top + box.height / 2) - rect.top) / (rect.height / 8));
            if (col >= 0 && col < 8 && row >= 0 && row < 8) {
              target = { file: flipped ? 7 - col : col, rank: flipped ? row : 7 - row };
            }
          }
          if (!target) { continue; }
          var letter = token.charAt(0) === "w" ? token.charAt(1).toUpperCase() : token.charAt(1);
          grid[(7 - target.rank) * 8 + target.file] = letter;
          placed++;
        }

        if (placed < 2) { return null; }

        var ranks = [];
        for (var r = 0; r < 8; r++) {
          var text = "";
          var empty = 0;
          for (var f = 0; f < 8; f++) {
            var cell = grid[r * 8 + f];
            if (cell === ".") {
              empty++;
            } else {
              if (empty > 0) { text += String(empty); empty = 0; }
              text += cell;
            }
          }
          if (empty > 0) { text += String(empty); }
          ranks.push(text);
        }

        return { placement: ranks.join("/"), flipped: flipped };
      }

      function moveContainer() {
        return document.querySelector(".vertical-move-list") ||
               document.querySelector(".play-controller-moves") ||
               document.querySelector("[class*='move-list']") ||
               document.querySelector(".move-list");
      }

      function cleanMove(raw) {
        var text = (raw || "").trim();
        text = text.split(String.fromCharCode(10)).join(" ");
        text = text.split(String.fromCharCode(9)).join(" ");
        while (text.length > 0) {
          var c = text.charAt(0);
          if (c >= "0" && c <= "9") { text = text.substring(1); continue; }
          if (c === "." || c === " ") { text = text.substring(1); continue; }
          break;
        }
        return text.trim();
      }

      function readMoves() {
        var container = moveContainer();
        if (!container) { return []; }
        var nodes = container.querySelectorAll(".node");
        var result = [];
        for (var i = 0; i < nodes.length; i++) {
          var sanEl = nodes[i].querySelector(".node-highlight-content") || nodes[i];
          var san = cleanMove(sanEl.textContent);
          if (san) { result.push(san); }
        }
        return result;
      }

      function readTurn() {
        var indicator = document.querySelector(".clock-player-turn") ||
                        document.querySelector("[class*='clock-player-turn']");
        if (!indicator) { return ""; }
        var holder = indicator.closest(".clock-component") || indicator.parentElement || indicator;
        var text = (holder.className || "") + " " + (indicator.className || "");
        var hasBlack = text.indexOf("black") >= 0;
        var hasWhite = text.indexOf("white") >= 0;
        if (hasBlack && !hasWhite) { return "b"; }
        if (hasWhite && !hasBlack) { return "w"; }
        return "";
      }

      function readGameOver() {
        return !!(document.querySelector("#game-over-modal") ||
                  document.querySelector(".game-over-modal-content") ||
                  document.querySelector("[data-test-element='game-over']") ||
                  document.querySelector(".modal-game-over"));
      }

      function readBoardID() {
        var holder = document.querySelector("[data-game-id]");
        if (holder) {
          var value = holder.getAttribute("data-game-id");
          if (value) { return "game:" + value; }
        }
        var link = document.querySelector("a[href*='/game/']");
        if (link) { return "href:" + link.getAttribute("href"); }
        return "url:" + location.host + location.pathname;
      }

      function post(payload) {
        try {
          if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers[HANDLER]) {
            window.webkit.messageHandlers[HANDLER].postMessage(payload);
            return true;
          }
        } catch (error) {
          return false;
        }
        return false;
      }

      function snapshot() {
        var board = readBoard();
        if (!board) { return; }
        var moves = readMoves();
        var sideToMove = readTurn();
        var gameOver = readGameOver();
        var boardID = readBoardID();
        var fingerprint = board.placement + "|" + sideToMove + "|" + moves.join(" ") + "|" +
                          (gameOver ? "1" : "0") + "|" + boardID;
        if (fingerprint === lastFingerprint) { return; }
        lastFingerprint = fingerprint;
        sequence++;
        post({
          session: session,
          sequence: sequence,
          url: location.href,
          placement: board.placement,
          sideToMove: sideToMove,
          moves: moves,
          userColor: board.flipped ? "b" : "w",
          isGameOver: gameOver,
          boardID: boardID
        });
      }

      function schedule() {
        if (debounceTimer) { return; }
        debounceTimer = setTimeout(function () {
          debounceTimer = null;
          snapshot();
        }, 140);
      }

      window.__cepLive = {
        version: 4,
        session: session,
        snapshot: snapshot,
        fingerprint: function () { return lastFingerprint; }
      };

      try {
        var observer = new MutationObserver(schedule);
        observer.observe(document.documentElement, {
          childList: true,
          subtree: true,
          attributes: true,
          attributeFilter: ["class", "style"]
        });
      } catch (error) {}

      // Safety net for virtualised lists and canvas updates that do not mutate
      // the observed attributes. The fingerprint guard keeps it silent.
      setInterval(snapshot, 1200);
      setTimeout(snapshot, 700);
    })();
    """
}
