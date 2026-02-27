import { motion } from 'framer-motion'
import {
  MessageSquare, FileText, Phone, Video,
  Users, WifiOff, Shield, Zap
} from 'lucide-react'

const features = [
  {
    icon: <MessageSquare className="w-6 h-6" />,
    title: 'Сообщения',
    desc: 'Текстовые чаты с доставкой в реальном времени',
    color: 'from-blue-500/20 to-blue-600/20 border-blue-500/30 text-blue-400',
  },
  {
    icon: <FileText className="w-6 h-6" />,
    title: 'Файлы',
    desc: 'Передача любых файлов напрямую между устройствами',
    color: 'from-green-500/20 to-green-600/20 border-green-500/30 text-green-400',
  },
  {
    icon: <Phone className="w-6 h-6" />,
    title: 'Голосовые звонки',
    desc: 'Чёткий звук, минимальная задержка через LAN',
    color: 'from-yellow-500/20 to-yellow-600/20 border-yellow-500/30 text-yellow-400',
  },
  {
    icon: <Video className="w-6 h-6" />,
    title: 'Видеозвонки',
    desc: 'HD-видео без кодеков облачных сервисов',
    color: 'from-red-500/20 to-red-600/20 border-red-500/30 text-red-400',
  },
  {
    icon: <Users className="w-6 h-6" />,
    title: 'Групповые чаты',
    desc: 'Общайся всей командой одновременно',
    color: 'from-purple-500/20 to-purple-600/20 border-purple-500/30 text-purple-400',
  },
  {
    icon: <WifiOff className="w-6 h-6" />,
    title: 'Без интернета',
    desc: 'Работает только по локальной сети, полностью офлайн',
    color: 'from-indigo-500/20 to-indigo-600/20 border-indigo-500/30 text-indigo-400',
  },
  {
    icon: <Shield className="w-6 h-6" />,
    title: 'Приватность',
    desc: 'Данные не покидают сеть, нет сбора аналитики',
    color: 'from-teal-500/20 to-teal-600/20 border-teal-500/30 text-teal-400',
  },
  {
    icon: <Zap className="w-6 h-6" />,
    title: 'Без регистрации',
    desc: 'Просто запусти приложение и начни общаться',
    color: 'from-orange-500/20 to-orange-600/20 border-orange-500/30 text-orange-400',
  },
]

export function FeaturesSection() {
  return (
    <section id="features" className="py-24 relative">
      {/* Background accent */}
      <div className="absolute inset-0 -z-10">
        <div className="absolute top-1/2 left-0 w-64 h-64 bg-purple-600/10 rounded-full blur-3xl" />
        <div className="absolute top-1/2 right-0 w-64 h-64 bg-indigo-600/10 rounded-full blur-3xl" />
      </div>

      <div className="container mx-auto px-4">
        <motion.div
          initial={{ opacity: 0, y: 30 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={{ once: true }}
          transition={{ duration: 0.6 }}
          className="text-center mb-16"
        >
          <p className="text-indigo-400 font-semibold text-sm uppercase tracking-widest mb-3">Возможности</p>
          <h2 className="text-4xl md:text-5xl font-bold text-white mb-4">
            Всё для общения
          </h2>
          <p className="text-white/50 text-lg max-w-xl mx-auto">
            Полноценный мессенджер для локальной сети — ничего лишнего
          </p>
        </motion.div>

        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
          {features.map((f, i) => (
            <motion.div
              key={i}
              initial={{ opacity: 0, y: 30 }}
              whileInView={{ opacity: 1, y: 0 }}
              viewport={{ once: true }}
              transition={{ duration: 0.4, delay: i * 0.07 }}
              whileHover={{ y: -4 }}
              className="group p-5 rounded-2xl border border-white/10 bg-white/5 backdrop-blur-sm hover:border-white/20 transition-all duration-300 cursor-default"
            >
              <div className={`w-11 h-11 rounded-xl bg-gradient-to-br ${f.color} border flex items-center justify-center mb-4 transition-transform group-hover:scale-110 duration-300`}>
                {f.icon}
              </div>
              <h3 className="text-white font-semibold mb-1">{f.title}</h3>
              <p className="text-white/45 text-sm leading-relaxed">{f.desc}</p>
            </motion.div>
          ))}
        </div>
      </div>
    </section>
  )
}
