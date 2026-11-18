import "package:flutter/material.dart";

ImageProvider? musicArtwork(String cover) {
  final value = cover.trim();
  final uri = Uri.tryParse(value.startsWith("//") ? "https:$value" : value);
  if (uri == null || !uri.hasAuthority) return null;
  if (uri.scheme != "http" && uri.scheme != "https") return null;

  final secure = uri.replace(scheme: "https");
  return NetworkImage(
    secure.toString(),
    headers: secure.host.endsWith(".hdslb.com")
        ? const {"Referer": "https://www.bilibili.com/"}
        : null,
  );
}
