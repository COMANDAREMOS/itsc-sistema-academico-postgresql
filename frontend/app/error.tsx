'use client';
export default function ErrorPage({ reset }: { error: Error; reset: () => void }) { return <main className="standalone"><section className="panel"><h1>No se pudo cargar esta pantalla</h1><p>Vuelve a intentarlo. Los cambios guardados se conservan.</p><button className="button" onClick={reset}>Volver a intentar</button></section></main>; }
