import { motion } from 'framer-motion'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Download, Wifi, WifiOff } from 'lucide-react'
import { FaAndroid, FaApple, FaLinux, FaWindows } from 'react-icons/fa'

const WINDOWS_URL = 'https://github.com/tuhlopuz1/piper/releases/download/release-piper/piper.exe'
const ANDROID_URL = 'https://github.com/tuhlopuz1/piper/releases/download/release-piper/app-release.apk'

const platforms = [
  {
    name: 'Windows',
    url: WINDOWS_URL,
    icon: <FaWindows className="w-5 h-5" />,
  },
  {
    name: 'Android',
    url: ANDROID_URL,
    icon: <FaAndroid className="w-5 h-5" />,
  },
  {
    name: 'macOS',
    url: '#',
    icon: <FaApple className="w-5 h-5" />,
    soon: true,
  },
  {
    name: 'Linux',
    url: '#',
    icon: <FaLinux className="w-5 h-5" />,
    soon: true,
  },
  {
    name: 'iOS',
    url: '#',
    icon: <FaApple className="w-5 h-5" />,
    soon: true,
  },
]

export function HeroSection() {
  return (
    <section className="relative min-h-screen flex items-center justify-center overflow-hidden pt-20">
      {/* Animated background */}
      <div className="absolute inset-0 -z-10">
        <div className="absolute top-1/4 left-1/4 w-96 h-96 bg-indigo-600/20 rounded-full blur-3xl animate-pulse" />
        <div className="absolute bottom-1/4 right-1/4 w-96 h-96 bg-purple-600/20 rounded-full blur-3xl animate-pulse [animation-delay:1s]" />
        <div className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 w-[600px] h-[600px] bg-indigo-900/10 rounded-full blur-3xl" />
      </div>

      <div className="container mx-auto px-4 py-20 text-center">
        {/* Badge */}
        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.5 }}
          className="flex justify-center mb-6"
        >
          <Badge variant="glow" className="gap-2 text-sm px-4 py-1.5">
            <WifiOff className="w-3.5 h-3.5" />
            Работает без интернета
          </Badge>
        </motion.div>

        {/* Logo + Title */}
        <motion.div
          initial={{ opacity: 0, y: 30 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.6, delay: 0.1 }}
          className="flex items-center justify-center gap-4 mb-6"
        >
          <div className="relative">
            <div className="w-16 h-16 rounded-2xl bg-gradient-to-br from-indigo-500 to-purple-600 flex items-center justify-center shadow-lg shadow-indigo-500/30 animate-pulse-glow">
              <img src="logo.png" alt="Piper" className="w-10 h-10 object-contain" onError={e => { (e.target as HTMLImageElement).style.display = 'none' }} />
              <Wifi className="w-8 h-8 text-white absolute" style={{ display: 'none' }} />
              <span className="text-white text-4xl font-bold">P</span>
            </div>
          </div>
          <h1 className="text-6xl md:text-8xl font-bold bg-gradient-to-r from-white via-indigo-200 to-purple-300 bg-clip-text text-transparent">
            Piper
          </h1>
        </motion.div>

        {/* Slogan */}
        <motion.p
          initial={{ opacity: 0, y: 30 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.6, delay: 0.2 }}
          className="text-2xl md:text-3xl font-semibold text-white/90 mb-4"
        >
          Общайся без интернета
        </motion.p>

        <motion.p
          initial={{ opacity: 0, y: 30 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.6, delay: 0.3 }}
          className="text-lg text-white/50 max-w-xl mx-auto mb-12 leading-relaxed"
        >
          Децентрализованный мессенджер для локальной сети — сообщения, файлы, голосовые и видеозвонки без серверов и регистрации.
        </motion.p>

        {/* Download buttons */}
        <motion.div
          initial={{ opacity: 0, y: 30 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.6, delay: 0.4 }}
          className="flex flex-wrap items-center justify-center gap-3 mb-16"
        >
          {platforms.map((p) => (
            <a key={p.name} href={p.url} className={p.soon ? 'pointer-events-none' : ''}>
              <Button
                variant={p.soon ? 'outline' : 'gradient'}
                size="lg"
                className={`gap-2 relative ${p.soon ? 'opacity-50' : 'shadow-lg shadow-indigo-500/20 hover:shadow-indigo-500/40 transition-shadow'}`}
                disabled={p.soon}
              >
                {p.icon}
                {p.name}
                {p.soon && (
                  <span className="absolute -top-2 -right-2 bg-white/20 text-white text-[10px] px-1.5 py-0.5 rounded-full leading-none">
                    скоро
                  </span>
                )}
                {!p.soon && <Download className="w-4 h-4 ml-1" />}
              </Button>
            </a>
          ))}
        </motion.div>

        {/* Mockup */}
        <motion.div
          initial={{ opacity: 0, y: 60 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.8, delay: 0.5 }}
          className="relative max-w-3xl mx-auto animate-float"
        >
          <div className="relative rounded-2xl overflow-hidden border border-white/10 shadow-2xl shadow-indigo-900/40 bg-white/5 backdrop-blur-sm">
            <img
              src="/mockup.png"
              alt="Piper App Preview"
              className="w-full object-cover"
              onError={(e) => {
                const target = e.target as HTMLImageElement
                const currentSrc = target.getAttribute('src') ?? ''

                // Try common typo and then show bundled placeholder.
                if (!currentSrc.endsWith('/mochup.png') && !currentSrc.endsWith('mochup.png')) {
                  target.setAttribute('src', '/mochup.png')
                  return
                }

                if (!currentSrc.endsWith('/mockup.svg') && !currentSrc.endsWith('mockup.svg')) {
                  target.setAttribute('src', '/mockup.svg')
                  return
                }

                target.style.display = 'none'
                const parent = target.parentElement!
                parent.innerHTML = `<div class="flex items-center justify-center h-64 text-white/20 text-sm gap-2"><svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24"><rect x="3" y="3" width="18" height="18" rx="2"/><circle cx="8.5" cy="8.5" r="1.5"/><path d="m21 15-5-5L5 21"/></svg>Добавьте mockup.png или mochup.png в папку public/</div>`
              }}
            />
          </div>
          {/* Glow */}
          <div className="absolute -inset-4 -z-10 bg-gradient-to-r from-indigo-600/20 to-purple-600/20 rounded-3xl blur-2xl" />
        </motion.div>
      </div>
    </section>
  )
}
