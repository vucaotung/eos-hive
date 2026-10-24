import { useId } from "react";

// Logo Enterprise OS: ô tổ ong (Tổ Ong, nơi mọi người cùng làm việc) có người và AI agent (tia sáng) cạnh nhau, dấu duyệt đỏ son ở góc.
// Bản vector gốc: public/logo.svg (dùng cho favicon và bộ icon PNG).
export default function Logo({ className = "size-8", title = "Enterprise OS" }) {
  const u = useId().replace(/:/g, "");
  return (
    <svg viewBox="0 0 64 64" className={`shrink-0 ${className}`} role="img" aria-label={title}>
<defs>
        <linearGradient id={`${u}g`} x1="8" y1="4" x2="56" y2="60" gradientUnits="userSpaceOnUse">
          <stop offset="0" stopColor="#3f5bd6"/><stop offset="1" stopColor="#1b2d86"/>
        </linearGradient>
        <linearGradient id={`${u}s`} x1="0" y1="0" x2="0" y2="1"><stop offset="0" stopColor="#fff" stopOpacity=".28"/><stop offset="1" stopColor="#fff" stopOpacity="0"/></linearGradient>
      </defs>
        <path d="M32 3.5 56 17.2c1.9 1.1 3 3.1 3 5.3v19c0 2.2-1.1 4.200-3 5.300L32 60.500 8 46.800c-1.900-1.100-3-3.100-3-5.300v-19c0-2.200 1.100-4.200 3-5.300z" fill={`url(#${u}g)`}/>
      <path d="M32 3.5 56 17.2c1.9 1.1 3 3.1 3 5.3v8C45 33 19 33 5 30.500v-8c0-2.200 1.100-4.200 3-5.300z" fill={`url(#${u}s)`}/>
        <circle cx="23" cy="27" r="6" fill="#fff"/>
      <path d="M12.500 46c0-5.300 4.600-8.800 10.500-8.800S33.500 40.700 33.500 46v1.500h-21z" fill="#fff"/>
      <path d="M44 20.500c.9 5.400 2.600 7.100 8 8-5.400.9-7.100 2.600-8 8-.9-5.400-2.600-7.100-8-8 5.400-.9 7.100-2.600 8-8z" fill="#fff"/>
      <path d="M50.500 38.500c.4 2.300 1.100 3 3.400 3.400-2.300.4-3 1.100-3.400 3.400-.4-2.300-1.100-3-3.400-3.400 2.300-.4 3-1.100 3.400-3.400z" fill="#c9d3ff"/>
        <circle cx="50" cy="15" r="6.200" fill="#d8392f" stroke="#fff" strokeWidth="2"/>
      <path d="M47 15.200l2.100 2.100 3.900-4.200" fill="none" stroke="#fff" strokeWidth="1.900" strokeLinecap="round" strokeLinejoin="round"/>
    </svg>
  );
}
