#!/usr/bin/env node
"use strict";

const net = require("node:net");
const tls = require("node:tls");

const MAX_HEADER_BYTES = 64 * 1024;

function usage() {
  console.log(
    [
      "Usage:",
      "  node scripts/ws_strip_extensions_proxy.js [--upstream ws://127.0.0.1:8080] [--listen-host 0.0.0.0] [--listen-port 18081]",
      "",
      "Options:",
      "  --upstream     Upstream codex app-server URL (ws:// or wss://)",
      "  --listen-host  Local bind host (default: 0.0.0.0)",
      "  --listen-port  Local bind port (default: 18081)",
      "  --help         Show this help",
    ].join("\n")
  );
}

function parseArgs(argv) {
  const result = {
    upstream: "ws://127.0.0.1:8080",
    listenHost: "0.0.0.0",
    listenPort: 18081,
  };

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === "--help" || arg === "-h") {
      usage();
      process.exit(0);
    }

    if (arg === "--upstream") {
      result.upstream = argv[index + 1] ?? "";
      index += 1;
      continue;
    }
    if (arg === "--listen-host") {
      result.listenHost = argv[index + 1] ?? "";
      index += 1;
      continue;
    }
    if (arg === "--listen-port") {
      result.listenPort = Number(argv[index + 1]);
      index += 1;
      continue;
    }

    console.error(`Unknown argument: ${arg}`);
    usage();
    process.exit(2);
  }

  if (!Number.isInteger(result.listenPort) || result.listenPort < 1 || result.listenPort > 65535) {
    throw new Error("listen-port must be an integer between 1 and 65535.");
  }

  let upstreamURL;
  try {
    upstreamURL = new URL(result.upstream);
  } catch {
    throw new Error(`Invalid upstream URL: ${result.upstream}`);
  }

  if (upstreamURL.protocol !== "ws:" && upstreamURL.protocol !== "wss:") {
    throw new Error("upstream URL must use ws:// or wss://");
  }

  result.upstreamURL = upstreamURL;
  return result;
}

function respondAndClose(socket, statusLine) {
  if (socket.destroyed) {
    return;
  }
  socket.end(`${statusLine}\r\nConnection: close\r\nContent-Length: 0\r\n\r\n`);
}

function parseRequest(rawHeaders) {
  const lines = rawHeaders.split("\r\n");
  const requestLine = lines.shift() ?? "";
  const [method, path, version] = requestLine.split(" ");

  if (method !== "GET" || !path || version !== "HTTP/1.1") {
    return null;
  }

  const headers = [];
  for (const line of lines) {
    if (!line) {
      continue;
    }
    const separator = line.indexOf(":");
    if (separator === -1) {
      continue;
    }
    const name = line.slice(0, separator).trim();
    const value = line.slice(separator + 1).trim();
    headers.push([name, value]);
  }

  return { path, headers };
}

function selectedUpstreamPath(upstreamURL, clientPath) {
  const hasCustomPath = upstreamURL.pathname && upstreamURL.pathname !== "/";
  const hasCustomQuery = upstreamURL.search && upstreamURL.search.length > 0;
  if (hasCustomPath || hasCustomQuery) {
    return `${upstreamURL.pathname || "/"}${upstreamURL.search || ""}`;
  }
  return clientPath;
}

function connectUpstream(upstreamURL) {
  const port =
    upstreamURL.port !== ""
      ? Number(upstreamURL.port)
      : upstreamURL.protocol === "wss:"
      ? 443
      : 80;
  if (upstreamURL.protocol === "wss:") {
    return tls.connect({
      host: upstreamURL.hostname,
      port,
      servername: upstreamURL.hostname,
    });
  }
  return net.connect({
    host: upstreamURL.hostname,
    port,
  });
}

function onConnection(clientSocket, config) {
  const remote = `${clientSocket.remoteAddress ?? "unknown"}:${clientSocket.remotePort ?? 0}`;
  let buffered = Buffer.alloc(0);
  let proxied = false;

  const onData = (chunk) => {
    if (proxied) {
      return;
    }
    buffered = Buffer.concat([buffered, chunk]);
    if (buffered.length > MAX_HEADER_BYTES) {
      console.warn(`[ws-proxy] dropped ${remote}: request headers too large`);
      respondAndClose(clientSocket, "HTTP/1.1 431 Request Header Fields Too Large");
      return;
    }

    const markerIndex = buffered.indexOf("\r\n\r\n");
    if (markerIndex === -1) {
      return;
    }

    clientSocket.removeListener("data", onData);
    const headerRaw = buffered.subarray(0, markerIndex).toString("latin1");
    const bodyRemainder = buffered.subarray(markerIndex + 4);
    const request = parseRequest(headerRaw);
    if (!request) {
      respondAndClose(clientSocket, "HTTP/1.1 400 Bad Request");
      return;
    }

    const outboundHeaders = [];
    for (const [name, value] of request.headers) {
      const lower = name.toLowerCase();
      if (lower === "host") {
        continue;
      }
      if (lower === "sec-websocket-extensions") {
        continue;
      }
      outboundHeaders.push([name, value]);
    }
    outboundHeaders.push(["Host", config.upstreamURL.host]);

    if (clientSocket.remoteAddress) {
      outboundHeaders.push(["X-Forwarded-For", clientSocket.remoteAddress]);
    }

    const outboundPath = selectedUpstreamPath(config.upstreamURL, request.path);
    const outboundRequest = [
      `GET ${outboundPath} HTTP/1.1`,
      ...outboundHeaders.map(([name, value]) => `${name}: ${value}`),
      "",
      "",
    ].join("\r\n");

    const upstreamSocket = connectUpstream(config.upstreamURL);
    const closeBoth = () => {
      if (!clientSocket.destroyed) {
        clientSocket.destroy();
      }
      if (!upstreamSocket.destroyed) {
        upstreamSocket.destroy();
      }
    };

    upstreamSocket.once("error", (error) => {
      console.warn(`[ws-proxy] upstream error for ${remote}: ${error.message}`);
      closeBoth();
    });
    clientSocket.once("error", () => {
      closeBoth();
    });

    upstreamSocket.once("connect", () => {
      upstreamSocket.write(outboundRequest, "latin1");
      if (bodyRemainder.length > 0) {
        upstreamSocket.write(bodyRemainder);
      }

      proxied = true;
      clientSocket.pipe(upstreamSocket);
      upstreamSocket.pipe(clientSocket);
    });
  };

  clientSocket.on("data", onData);
}

function main() {
  let config;
  try {
    config = parseArgs(process.argv.slice(2));
  } catch (error) {
    console.error(`[ws-proxy] ${error.message}`);
    process.exit(2);
    return;
  }

  const server = net.createServer((socket) => onConnection(socket, config));
  server.on("error", (error) => {
    console.error(`[ws-proxy] server error: ${error.message}`);
    process.exitCode = 1;
  });

  server.listen(config.listenPort, config.listenHost, () => {
    console.log(
      `[ws-proxy] listening on ws://${config.listenHost}:${config.listenPort} -> ${config.upstream}`
    );
  });
}

main();
