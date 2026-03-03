import { motion } from 'framer-motion'
import { Button } from '@/components/ui/button'
import { Download, HardDrive } from 'lucide-react'
import { FaAndroid, FaApple, FaLinux, FaWindows } from 'react-icons/fa'

const WINDOWS_URL = 'https://github.com/tuhlopuz1/piper/releases/download/release-piper/piper.exe'
const ANDROID_URL = 'https://github.com/tuhlopuz1/piper/releases/download/release-piper/app-release.apk'

const platforms = [
  {
    name: 'Windows',
    version: 'Windows 10/11',
    size: '~25 MB',
    url: WINDOWS_URL,
    available: true,
    icon: <FaWindows className="w-10 h-10 text-indigo-400" />,
  },
  {
    name: 'Android',
    version: 'Android 8.0+',
    size: '~30 MB',
    url: ANDROID_URL,
    available: true,
    icon: <FaAndroid className="w-10 h-10 text-indigo-400" />,
  },
  {
    name: 'macOS',
    version: 'macOS 12+',
    size: '~28 MB',
    url: '#',
    available: false,
    icon: <FaApple className="w-10 h-10 text-white/40" />,
  },
  {
    name: 'Linux',
    version: 'Ubuntu, Fedora...',
    size: '~22 MB',
    url: '#',
    available: false,
    icon: <FaLinux className="w-10 h-10 text-white/40" />,
  },
  {
    name: 'iOS',
    version: 'iOS 15+',
    size: '~20 MB',
    url: '#',
    available: false,
    icon: <FaApple className="w-10 h-10 text-white/40" />,
  },
]

export function DownloadSection() {
  return (
    <section id="download" className="py-24 relative">
      <div className="absolute inset-0 -z-10">
        <div className="absolute inset-0 bg-gradient-to-b from-transparent via-indigo-950/30 to-transparent" />
      </div>

      <div className="container mx-auto px-4">
        <motion.div
          initial={{ opacity: 0, y: 30 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={{ once: true }}
          transition={{ duration: 0.6 }}
          className="text-center mb-16"
        >
          <p className="text-indigo-400 font-semibold text-sm uppercase tracking-widest mb-3">Скачать</p>
          <h2 className="text-4xl md:text-5xl font-bold text-white mb-4">
            Выбери свою платформу
          </h2>
          <p className="text-white/50 text-lg max-w-lg mx-auto">
            Piper доступен для всех популярных ОС. Некоторые платформы пока в разработке.
          </p>
        </motion.div>

        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-5 gap-4 max-w-5xl mx-auto">
          {platforms.map((p, i) => (
            <motion.div
              key={i}
              initial={{ opacity: 0, scale: 0.95 }}
              whileInView={{ opacity: 1, scale: 1 }}
              viewport={{ once: true }}
              transition={{ duration: 0.4, delay: i * 0.08 }}
            >
              <a
                href={p.available ? p.url : undefined}
                className={`block h-full ${!p.available ? 'cursor-not-allowed' : ''}`}
              >
                <div
                  className={`relative group h-full p-6 rounded-2xl border text-center transition-all duration-300 ${
                    p.available
                      ? 'border-indigo-500/40 bg-indigo-500/5 hover:border-indigo-500/70 hover:bg-indigo-500/10 hover:-translate-y-1 shadow-lg shadow-indigo-900/20'
                      : 'border-white/10 bg-white/5 opacity-50'
                  }`}
                >
                  {!p.available && (
                    <span className="absolute top-3 right-3 text-[10px] bg-white/10 text-white/50 px-2 py-0.5 rounded-full">
                      скоро
                    </span>
                  )}
                  <div className="flex justify-center mb-4">{p.icon}</div>
                  <h3 className="text-white font-semibold mb-1">{p.name}</h3>
                  <p className="text-white/40 text-xs mb-1">{p.version}</p>
                  <div className="flex items-center justify-center gap-1 text-white/30 text-xs mb-4">
                    <HardDrive className="w-3 h-3" />
                    {p.size}
                  </div>
                  {p.available && (
                    <Button variant="gradient" size="sm" className="w-full gap-1.5">
                      <Download className="w-3.5 h-3.5" />
                      Скачать
                    </Button>
                  )}
                </div>
              </a>
            </motion.div>
          ))}
        </div>
      </div>
    </section>
  )
}
