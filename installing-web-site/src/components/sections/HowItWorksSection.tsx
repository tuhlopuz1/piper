import { motion } from 'framer-motion'
import { Wifi, Search, MessageSquare, Zap } from 'lucide-react'

const steps = [
  {
    icon: <Wifi className="w-7 h-7" />,
    step: '01',
    title: 'Подключись к Wi-Fi',
    desc: 'Убедись, что устройства находятся в одной локальной сети — домашний роутер, офисная сеть или мобильная точка доступа.',
  },
  {
    icon: <Search className="w-7 h-7" />,
    step: '02',
    title: 'Автообнаружение',
    desc: 'Piper автоматически находит все устройства с приложением в сети через mDNS. Никаких ручных настроек.',
  },
  {
    icon: <MessageSquare className="w-7 h-7" />,
    step: '03',
    title: 'Начни общение',
    desc: 'Отправляй сообщения, файлы, звони голосом и видео. Всё работает напрямую между устройствами.',
  },
  {
    icon: <Zap className="w-7 h-7" />,
    step: '04',
    title: 'Минимальная задержка',
    desc: 'Прямое P2P-соединение без промежуточных серверов — скорость ограничена только возможностями вашей сети.',
  },
]

export function HowItWorksSection() {
  return (
    <section id="how-it-works" className="py-24 relative">
      <div className="container mx-auto px-4">
        <motion.div
          initial={{ opacity: 0, y: 30 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={{ once: true }}
          transition={{ duration: 0.6 }}
          className="text-center mb-16"
        >
          <p className="text-indigo-400 font-semibold text-sm uppercase tracking-widest mb-3">Как это работает</p>
          <h2 className="text-4xl md:text-5xl font-bold text-white mb-4">
            Просто и понятно
          </h2>
          <p className="text-white/50 text-lg max-w-xl mx-auto">
            Всего четыре шага — и ты уже общаешься с командой без интернета
          </p>
        </motion.div>

        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6 relative">
          {/* Connector line */}
          <div className="hidden lg:block absolute top-12 left-[12.5%] right-[12.5%] h-px bg-gradient-to-r from-transparent via-indigo-500/40 to-transparent" />

          {steps.map((step, i) => (
            <motion.div
              key={i}
              initial={{ opacity: 0, y: 40 }}
              whileInView={{ opacity: 1, y: 0 }}
              viewport={{ once: true }}
              transition={{ duration: 0.5, delay: i * 0.12 }}
              className="relative group"
            >
              <div className="relative z-10 p-6 rounded-2xl border border-white/10 bg-white/5 backdrop-blur-sm hover:border-indigo-500/40 hover:bg-white/8 transition-all duration-300">
                {/* Step number */}
                <div className="text-[56px] font-black text-white/5 absolute top-4 right-4 leading-none select-none">
                  {step.step}
                </div>
                {/* Icon */}
                <div className="w-12 h-12 rounded-xl bg-gradient-to-br from-indigo-500/20 to-purple-500/20 border border-indigo-500/30 flex items-center justify-center text-indigo-400 mb-4 group-hover:from-indigo-500/30 group-hover:to-purple-500/30 transition-all">
                  {step.icon}
                </div>
                <h3 className="text-lg font-semibold text-white mb-2">{step.title}</h3>
                <p className="text-white/50 text-sm leading-relaxed">{step.desc}</p>
              </div>
            </motion.div>
          ))}
        </div>
      </div>
    </section>
  )
}
