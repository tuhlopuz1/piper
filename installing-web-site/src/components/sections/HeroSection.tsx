import { motion } from 'framer-motion'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { Download, Wifi, WifiOff } from 'lucide-react'

const WINDOWS_URL = 'https://github.com/tuhlopuz1/piper/releases/download/release-piper/piper.exe'
const ANDROID_URL = 'https://github.com/tuhlopuz1/piper/releases/download/release-piper/app-release.apk'

const platforms = [
  {
    name: 'Windows',
    url: WINDOWS_URL,
    icon: (
      <svg viewBox="0 0 24 24" className="w-5 h-5 fill-current">
        <path d="M0 3.449L9.75 2.1v9.451H0m10.949-9.602L24 0v11.4H10.949M0 12.6h9.75v9.451L0 20.699M10.949 12.6H24V24l-12.9-1.801" />
      </svg>
    ),
  },
  {
    name: 'Android',
    url: ANDROID_URL,
    icon: (
      <svg viewBox="0 0 24 24" className="w-5 h-5 fill-current">
        <path d="M17.523 15.341a.85.85 0 0 1-.848.848.85.85 0 0 1-.848-.848.85.85 0 0 1 .848-.848.85.85 0 0 1 .848.848m-9.35 0a.85.85 0 0 1-.848.848.85.85 0 0 1-.848-.848.85.85 0 0 1 .848-.848.85.85 0 0 1 .848.848M17.7 9.386l1.674-2.898a.348.348 0 0 0-.127-.476.348.348 0 0 0-.476.127l-1.695 2.934A10.255 10.255 0 0 0 12 8.107c-1.485 0-2.894.318-4.076.966L6.229 6.139a.348.348 0 0 0-.476-.127.348.348 0 0 0-.127.476L7.3 9.386C4.95 10.7 3.35 13.07 3.35 15.8H20.65c0-2.73-1.6-5.1-3.95-6.414" />
      </svg>
    ),
  },
  {
    name: 'macOS',
    url: '#',
    icon: (
      <svg viewBox="0 0 24 24" className="w-5 h-5 fill-current">
        <path d="M12.152 6.896c-.948 0-2.415-1.078-3.96-1.04-2.04.027-3.91 1.183-4.961 3.014-2.117 3.675-.546 9.103 1.519 12.09 1.013 1.454 2.208 3.09 3.792 3.039 1.52-.065 2.09-.987 3.935-.987 1.831 0 2.35.987 3.96.948 1.637-.026 2.676-1.48 3.676-2.948 1.156-1.688 1.636-3.325 1.662-3.415-.039-.013-3.182-1.221-3.22-4.857-.026-3.04 2.48-4.494 2.597-4.559-1.429-2.09-3.623-2.324-4.39-2.376-2-.156-3.675 1.09-4.61 1.09zM15.53 3.83c.843-1.012 1.4-2.427 1.245-3.83-1.207.052-2.662.805-3.532 1.818-.78.896-1.454 2.338-1.273 3.714 1.338.104 2.715-.688 3.559-1.701" />
      </svg>
    ),
    soon: true,
  },
  {
    name: 'Linux',
    url: '#',
    icon: (
      <svg viewBox="0 0 24 24" className="w-5 h-5 fill-current">
        <path d="M12.504 0c-.155 0-.315.008-.48.021-4.226.333-3.105 4.807-3.17 6.298-.076 1.092-.3 1.953-1.05 3.02-.885 1.051-2.127 2.75-2.716 4.521-.278.832-.41 1.684-.287 2.489a.424.424 0 00-.11.135c-.26.268-.45.6-.663.839-.199.199-.485.267-.797.4-.313.136-.658.269-.864.68-.09.189-.136.394-.132.602 0 .199.027.4.055.536.058.399.116.728.04.97-.249.68-.28 1.145-.106 1.484.174.334.535.47.94.601.81.2 1.91.135 2.774.6.926.466 1.866.67 2.616.47.526-.116.97-.464 1.208-.946.587-.003 1.23-.149 1.65-.284.414-.135.87-.357 1.192-.658.06-.056.12-.123.173-.202.48.267.99.44 1.472.44.43 0 .826-.132 1.15-.363.326-.236.57-.567.725-.975.153-.408.195-.894.12-1.403-.076-.51-.261-1.024-.486-1.454-.226-.43-.492-.78-.713-.992l-.018-.018c.166-.292.282-.63.364-1.018.08-.39.12-.82.108-1.264-.012-.452-.072-.92-.194-1.373-.145-.54-.38-1.072-.698-1.56-.318-.49-.712-.926-1.16-1.31-.447-.384-.965-.713-1.54-.964-.577-.25-1.215-.42-1.9-.457-.156-.008-.315-.012-.477-.012zm-.527 1.12c.32 0 .627.006.924.02.58.03 1.09.17 1.539.369.45.198.842.47 1.18.78.337.312.62.668.846 1.062.226.394.4.818.505 1.258.107.44.158.898.168 1.348.01.443-.022.882-.095 1.284-.073.402-.19.77-.35 1.088.228.249.465.58.667.97.202.388.36.845.435 1.333.075.488.042.99-.095 1.428-.13.44-.35.828-.64 1.112.15.207.32.546.453.965.134.422.218.916.164 1.387-.054.47-.24.92-.556 1.213-.316.293-.758.435-1.251.368a4.01 4.01 0 01-.97-.267c-.16.237-.36.448-.587.622-.228.173-.49.31-.774.404-.28.094-.58.14-.88.127-.3-.014-.6-.085-.878-.219-.278-.134-.53-.33-.73-.585a.83.83 0 01-.116-.32 2.85 2.85 0 01-.88.137c-.302 0-.593-.037-.868-.12a3.53 3.53 0 01-.79-.36 2.97 2.97 0 01-.633-.62c-.248.076-.505.12-.76.12-.56 0-1.098-.16-1.562-.45a3.5 3.5 0 01-1.076-1.16c-.264-.465-.403-.99-.41-1.53-.006-.54.115-1.087.338-1.572a6.23 6.23 0 01.895-1.386c.37-.436.787-.833 1.193-1.206.407-.373.804-.722 1.11-1.066.308-.344.525-.682.614-1.03.09-.35.057-.712-.02-1.07-.154-.72-.47-1.44-.648-2.084-.178-.646-.21-1.218.01-1.64.108-.212.288-.39.53-.514a2.028 2.028 0 01.853-.192z" />
      </svg>
    ),
    soon: true,
  },
  {
    name: 'iOS',
    url: '#',
    icon: (
      <svg viewBox="0 0 24 24" className="w-5 h-5 fill-current">
        <path d="M18.71 19.5c-.83 1.24-1.71 2.45-3.05 2.47-1.34.03-1.77-.79-3.29-.79-1.53 0-2 .77-3.27.82-1.31.05-2.3-1.32-3.14-2.53C4.25 17 2.94 12.45 4.7 9.39c.87-1.52 2.43-2.48 4.12-2.51 1.28-.02 2.5.87 3.29.87.78 0 2.26-1.07 3.8-.91.65.03 2.47.26 3.64 1.98-.09.06-2.17 1.28-2.15 3.81.03 3.02 2.65 4.03 2.68 4.04-.03.07-.42 1.44-1.38 2.83M13 3.5c.73-.83 1.94-1.46 2.94-1.5.13 1.17-.34 2.35-1.04 3.19-.69.85-1.83 1.51-2.95 1.42-.15-1.15.41-2.35 1.05-3.11z" />
      </svg>
    ),
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
              src="mockup.png"
              alt="Piper App Preview"
              className="w-full object-cover"
              onError={(e) => {
                const target = e.target as HTMLImageElement
                target.style.display = 'none'
                const parent = target.parentElement!
                parent.innerHTML = `<div class="flex items-center justify-center h-64 text-white/20 text-sm gap-2"><svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24"><rect x="3" y="3" width="18" height="18" rx="2"/><circle cx="8.5" cy="8.5" r="1.5"/><path d="m21 15-5-5L5 21"/></svg>Добавьте mockup.png в папку public/</div>`
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
