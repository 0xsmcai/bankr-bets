import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  output: "export",
  basePath: "/bankr-bets",
  images: { unoptimized: true },
};

export default nextConfig;
