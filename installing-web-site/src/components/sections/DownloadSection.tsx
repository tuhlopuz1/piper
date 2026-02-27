import { motion } from 'framer-motion'
import { Button } from '@/components/ui/button'
import { Download, HardDrive } from 'lucide-react'

const WINDOWS_URL = 'https://github.com/tuhlopuz1/piper/releases/download/release-piper/piper.exe'
const ANDROID_URL = 'https://github.com/tuhlopuz1/piper/releases/download/release-piper/app-release.apk'

const platforms = [
  {
    name: 'Windows',
    version: 'Windows 10/11',
    size: '~25 MB',
    url: WINDOWS_URL,
    available: true,
    icon: (
      <svg viewBox="0 0 24 24" className="w-10 h-10 fill-current text-blue-400">
        <path d="M0 3.449L9.75 2.1v9.451H0m10.949-9.602L24 0v11.4H10.949M0 12.6h9.75v9.451L0 20.699M10.949 12.6H24V24l-12.9-1.801" />
      </svg>
    ),
  },
  {
    name: 'Android',
    version: 'Android 8.0+',
    size: '~30 MB',
    url: ANDROID_URL,
    available: true,
    icon: (
      <svg viewBox="0 0 24 24" className="w-10 h-10 fill-current text-green-400">
        <path d="M17.523 15.341a.85.85 0 0 1-.848.848.85.85 0 0 1-.848-.848.85.85 0 0 1 .848-.848.85.85 0 0 1 .848.848m-9.35 0a.85.85 0 0 1-.848.848.85.85 0 0 1-.848-.848.85.85 0 0 1 .848-.848.85.85 0 0 1 .848.848M17.7 9.386l1.674-2.898a.348.348 0 0 0-.127-.476.348.348 0 0 0-.476.127l-1.695 2.934A10.255 10.255 0 0 0 12 8.107c-1.485 0-2.894.318-4.076.966L6.229 6.139a.348.348 0 0 0-.476-.127.348.348 0 0 0-.127.476L7.3 9.386C4.95 10.7 3.35 13.07 3.35 15.8H20.65c0-2.73-1.6-5.1-3.95-6.414" />
      </svg>
    ),
  },
  {
    name: 'macOS',
    version: 'macOS 12+',
    size: '~28 MB',
    url: '#',
    available: false,
    icon: (
      <svg viewBox="0 0 24 24" className="w-10 h-10 fill-current text-white/40">
        <path d="M12.152 6.896c-.948 0-2.415-1.078-3.96-1.04-2.04.027-3.91 1.183-4.961 3.014-2.117 3.675-.546 9.103 1.519 12.09 1.013 1.454 2.208 3.09 3.792 3.039 1.52-.065 2.09-.987 3.935-.987 1.831 0 2.35.987 3.96.948 1.637-.026 2.676-1.48 3.676-2.948 1.156-1.688 1.636-3.325 1.662-3.415-.039-.013-3.182-1.221-3.22-4.857-.026-3.04 2.48-4.494 2.597-4.559-1.429-2.09-3.623-2.324-4.39-2.376-2-.156-3.675 1.09-4.61 1.09zM15.53 3.83c.843-1.012 1.4-2.427 1.245-3.83-1.207.052-2.662.805-3.532 1.818-.78.896-1.454 2.338-1.273 3.714 1.338.104 2.715-.688 3.559-1.701" />
      </svg>
    ),
  },
  {
    name: 'Linux',
    version: 'Ubuntu, Fedora...',
    size: '~22 MB',
    url: '#',
    available: false,
    icon: (
      <svg viewBox="0 0 24 24" className="w-10 h-10 fill-current text-white/40">
        <path d="M12.504 0c-.155 0-.315.008-.48.021-4.226.333-3.105 4.807-3.17 6.298-.076 1.092-.3 1.953-1.05 3.02-.885 1.051-2.127 2.75-2.716 4.521-.278.832-.41 1.684-.287 2.489a.424.424 0 00-.11.135c-.26.268-.45.6-.663.839-.199.199-.485.267-.797.4-.313.136-.658.269-.864.68-.09.189-.136.394-.132.602 0 .199.027.4.055.536.058.399.116.728.04.97-.249.68-.28 1.145-.106 1.484.174.334.535.47.94.601.81.2 1.91.135 2.774.6.926.466 1.866.67 2.616.47.526-.116.97-.464 1.208-.946.587-.003 1.23-.149 1.65-.284.414-.135.87-.357 1.192-.658.06-.056.12-.123.173-.202.48.267.99.44 1.472.44.43 0 .826-.132 1.15-.363.326-.236.57-.567.725-.975.153-.408.195-.894.12-1.403-.076-.51-.261-1.024-.486-1.454-.226-.43-.492-.78-.713-.992l-.018-.018c.166-.292.282-.63.364-1.018.08-.39.12-.82.108-1.264-.012-.452-.072-.92-.194-1.373-.145-.54-.38-1.072-.698-1.56-.318-.49-.712-.926-1.16-1.31-.447-.384-.965-.713-1.54-.964-.577-.25-1.215-.42-1.9-.457-.156-.008-.315-.012-.477-.012z" />
      </svg>
    ),
  },
  {
    name: 'iOS',
    version: 'iOS 15+',
    size: '~20 MB',
    url: '#',
    available: false,
    icon: (
      <svg viewBox="0 0 24 24" className="w-10 h-10 fill-current text-white/40">
        <path d="M18.71 19.5c-.83 1.24-1.71 2.45-3.05 2.47-1.34.03-1.77-.79-3.29-.79-1.53 0-2 .77-3.27.82-1.31.05-2.3-1.32-3.14-2.53C4.25 17 2.94 12.45 4.7 9.39c.87-1.52 2.43-2.48 4.12-2.51 1.28-.02 2.5.87 3.29.87.78 0 2.26-1.07 3.8-.91.65.03 2.47.26 3.64 1.98-.09.06-2.17 1.28-2.15 3.81.03 3.02 2.65 4.03 2.68 4.04-.03.07-.42 1.44-1.38 2.83M13 3.5c.73-.83 1.94-1.46 2.94-1.5.13 1.17-.34 2.35-1.04 3.19-.69.85-1.83 1.51-2.95 1.42-.15-1.15.41-2.35 1.05-3.11z" />
      </svg>
    ),
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
