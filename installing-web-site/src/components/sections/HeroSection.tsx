import { motion } from 'framer-motion'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Download, Wifi, WifiOff } from 'lucide-react'
import { FaAndroid, FaApple, FaLinux, FaWindows } from 'react-icons/fa'

const WINDOWS_URL = 'https://github.com/tuhlopuz1/piper/releases/latest/download/piper-setup.exe'
const ANDROID_URL = 'https://github.com/tuhlopuz1/piper/releases/latest/download/app-release.apk'
const MACOS_URL = 'https://github.com/tuhlopuz1/piper/releases/latest/download/piper-macos.dmg'
const LINUX_URL = 'https://github.com/tuhlopuz1/piper/releases/latest/download/piper-linux-amd64.deb'

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
    url: MACOS_URL,
    icon: <FaApple className="w-5 h-5" />,
  },
  {
    name: 'Linux',
    url: LINUX_URL,
    icon: <FaLinux className="w-5 h-5" />,
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

      </div>
    </section>
  )
}
