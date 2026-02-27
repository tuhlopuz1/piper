import { useState } from 'react'
import { motion, AnimatePresence } from 'framer-motion'
import { ChevronLeft, ChevronRight } from 'lucide-react'

const screenshots = [
  { src: 'screenshots/chat.png', label: 'Чат' },
  { src: 'screenshots/call.png', label: 'Звонок' },
  { src: 'screenshots/contacts.png', label: 'Контакты' },
  { src: 'screenshots/files.png', label: 'Файлы' },
]

const placeholderLabels: Record<string, string> = {
  'Чат': 'screenshots/chat.png',
  'Звонок': 'screenshots/call.png',
  'Контакты': 'screenshots/contacts.png',
  'Файлы': 'screenshots/files.png',
}

export function ScreenshotsSection() {
  const [active, setActive] = useState(0)
  const [direction, setDirection] = useState(1)

  const go = (dir: number) => {
    setDirection(dir)
    setActive((prev) => (prev + dir + screenshots.length) % screenshots.length)
  }

  return (
    <section id="screenshots" className="py-24 relative overflow-hidden">
      <div className="container mx-auto px-4">
        <motion.div
          initial={{ opacity: 0, y: 30 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={{ once: true }}
          transition={{ duration: 0.6 }}
          className="text-center mb-16"
        >
          <p className="text-indigo-400 font-semibold text-sm uppercase tracking-widest mb-3">Интерфейс</p>
          <h2 className="text-4xl md:text-5xl font-bold text-white mb-4">
            Скриншоты
          </h2>
          <p className="text-white/50 text-lg">
            Чистый и интуитивный дизайн
          </p>
        </motion.div>

        {/* Tab nav */}
        <div className="flex justify-center gap-2 mb-8">
          {screenshots.map((s, i) => (
            <button
              key={i}
              onClick={() => { setDirection(i > active ? 1 : -1); setActive(i) }}
              className={`px-4 py-1.5 rounded-full text-sm font-medium transition-all ${
                i === active
                  ? 'bg-indigo-600 text-white shadow-lg shadow-indigo-500/30'
                  : 'text-white/40 hover:text-white/70 border border-white/10 hover:border-white/20'
              }`}
            >
              {s.label}
            </button>
          ))}
        </div>

        {/* Carousel */}
        <div className="relative max-w-2xl mx-auto">
          <div className="relative rounded-2xl overflow-hidden border border-white/10 bg-white/5 backdrop-blur-sm aspect-[16/10]">
            <AnimatePresence mode="wait" custom={direction}>
              <motion.div
                key={active}
                custom={direction}
                variants={{
                  enter: (d: number) => ({ x: d * 60, opacity: 0 }),
                  center: { x: 0, opacity: 1 },
                  exit: (d: number) => ({ x: -d * 60, opacity: 0 }),
                }}
                initial="enter"
                animate="center"
                exit="exit"
                transition={{ duration: 0.35, ease: 'easeInOut' }}
                className="absolute inset-0"
              >
                <img
                  src={screenshots[active].src}
                  alt={screenshots[active].label}
                  className="w-full h-full object-cover"
                  onError={(e) => {
                    const t = e.target as HTMLImageElement
                    t.style.display = 'none'
                    const p = t.parentElement!
                    p.innerHTML = `<div class="flex flex-col items-center justify-center h-full text-white/20 gap-3"><svg xmlns="http://www.w3.org/2000/svg" width="48" height="48" fill="none" stroke="currentColor" stroke-width="1.5" viewBox="0 0 24 24"><rect x="3" y="3" width="18" height="18" rx="2"/><circle cx="8.5" cy="8.5" r="1.5"/><path d="m21 15-5-5L5 21"/></svg><p class="text-sm">Добавьте: public/${placeholderLabels[screenshots[active]?.label ?? ''] ?? ''}</p></div>`
                  }}
                />
              </motion.div>
            </AnimatePresence>
          </div>

          {/* Glow */}
          <div className="absolute -inset-6 -z-10 bg-gradient-to-r from-indigo-600/15 to-purple-600/15 rounded-3xl blur-2xl" />

          {/* Controls */}
          <button
            onClick={() => go(-1)}
            className="absolute left-0 top-1/2 -translate-y-1/2 -translate-x-1/2 w-10 h-10 rounded-full border border-white/20 bg-black/40 backdrop-blur-sm flex items-center justify-center text-white hover:bg-white/10 transition-colors z-10"
          >
            <ChevronLeft className="w-5 h-5" />
          </button>
          <button
            onClick={() => go(1)}
            className="absolute right-0 top-1/2 -translate-y-1/2 translate-x-1/2 w-10 h-10 rounded-full border border-white/20 bg-black/40 backdrop-blur-sm flex items-center justify-center text-white hover:bg-white/10 transition-colors z-10"
          >
            <ChevronRight className="w-5 h-5" />
          </button>
        </div>

        {/* Dots */}
        <div className="flex justify-center gap-2 mt-6">
          {screenshots.map((_, i) => (
            <button
              key={i}
              onClick={() => { setDirection(i > active ? 1 : -1); setActive(i) }}
              className={`rounded-full transition-all ${i === active ? 'w-6 h-2 bg-indigo-500' : 'w-2 h-2 bg-white/20 hover:bg-white/40'}`}
            />
          ))}
        </div>
      </div>
    </section>
  )
}
