import type { Metadata } from 'next'
import { Providers } from './providers'
import './globals.css'

export const metadata: Metadata = {
  title: 'Bankr Bets',
  description: 'Parimutuel binary prediction market on Base. Bet UP or DOWN on token prices.',
}

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className="h-full">
      <head>
        <link href="https://fonts.googleapis.com/css2?family=Space+Grotesk:wght@400;600;700&family=Space+Mono:wght@400;700&display=swap" rel="stylesheet" />
        <link href="https://api.fontshare.com/v2/css?f[]=satoshi@300,400,500,700&display=swap" rel="stylesheet" />
      </head>
      <body className="min-h-full flex flex-col bg-[#1a1210] text-[#d4d0c8]">
        <Providers>
          {children}
        </Providers>
      </body>
    </html>
  )
}
