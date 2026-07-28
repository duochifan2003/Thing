import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "人物事件库｜个人本地档案",
  description: "以时间线整理人物与事件的本地优先个人知识库。",
  icons: {
    icon: "/favicon.svg",
    shortcut: "/favicon.svg",
    apple: "/icon-192.png",
  },
  manifest: "/manifest.webmanifest",
  appleWebApp: { capable: true, title: "人物事件库" },
  other: { "mobile-web-app-capable": "yes" },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="zh-CN">
      <body>{children}</body>
    </html>
  );
}
