import type { Metadata } from 'next';
import './globals.css';

export const metadata: Metadata = {
  title: 'Harness · Models prototype',
  description:
    'Choose models for your agents, from cloud accounts, your machines, your team or public providers. A local prototype with simulated activity.',
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en" className="dark">
      <body>{children}</body>
    </html>
  );
}
