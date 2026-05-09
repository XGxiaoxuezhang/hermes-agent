export function Backdrop() {
  return (
    <>
      <div
        aria-hidden
        className="pointer-events-none fixed inset-0 z-[1]"
        style={{
          background:
            "linear-gradient(180deg, #0b0f10 0%, #0d1213 48%, #090c0d 100%)",
        }}
      />

      <div
        aria-hidden
        className="pointer-events-none fixed inset-0 z-[2]"
        style={{
          backgroundImage:
            "linear-gradient(rgba(255,255,255,0.035) 1px, transparent 1px), linear-gradient(90deg, rgba(255,255,255,0.03) 1px, transparent 1px)",
          backgroundSize: "32px 32px",
          maskImage:
            "linear-gradient(180deg, rgba(0,0,0,0.7), rgba(0,0,0,0.18) 42%, transparent 86%)",
          opacity: 0.45,
        }}
      />

      <div
        aria-hidden
        className="pointer-events-none fixed inset-x-0 top-0 z-[3] h-px"
        style={{
          background:
            "linear-gradient(90deg, transparent, rgba(91, 221, 196, 0.42), rgba(245, 185, 95, 0.32), transparent)",
        }}
      />
    </>
  );
}
