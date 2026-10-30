import type { Metadata } from 'next';
import './styles/style.css';
import './styles/institucional.css';
import './styles/identidad-v2.css';
import './styles/dark.css';
import './styles/gestion.css';
import './styles/operaciones.css';
import './globals.css';

export const metadata: Metadata = {
  title: 'Instituto Tecnológico Santa Cruz · Gestión académica',
  description: 'Sistema académico del Instituto Tecnológico Santa Cruz.',
  icons: { icon: '/assets/logo-itsc-v2.png' },
};

const themeScript = `try{var t=localStorage.getItem('itsc-theme');document.documentElement.dataset.theme=t==='dark'?'dark':'light'}catch(e){}`;

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="es" suppressHydrationWarning><head><script dangerouslySetInnerHTML={{ __html: themeScript }} /></head><body>{children}</body></html>;
}
