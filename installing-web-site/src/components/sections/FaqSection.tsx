import { motion } from 'framer-motion'
import { Accordion, AccordionContent, AccordionItem, AccordionTrigger } from '@/components/ui/accordion'

const faqs = [
  {
    q: 'Нужен ли интернет для работы Piper?',
    a: 'Нет. Piper работает исключительно в локальной сети (LAN/Wi-Fi). Интернет не требуется ни для обнаружения устройств, ни для передачи сообщений и файлов, ни для звонков.',
  },
  {
    q: 'Какие операционные системы поддерживаются?',
    a: 'Сейчас доступны версии для Windows и Android. В разработке: macOS, Linux и iOS. Следите за обновлениями на GitHub.',
  },
  {
    q: 'Безопасно ли использовать Piper?',
    a: 'Все данные передаются только внутри вашей локальной сети и никогда не покидают её. Нет облачных серверов, нет сбора аналитики. Ваши переписки остаются только между участниками сети.',
  },
  {
    q: 'Сколько человек может быть в сети одновременно?',
    a: 'Теоретически ограничений нет — всё зависит от пропускной способности вашего роутера и мощности устройств. На практике комфортно работает с десятками участников.',
  },
  {
    q: 'Нужна ли регистрация или учётная запись?',
    a: 'Нет. Просто установите приложение, введите имя — и вы уже в сети. Никаких аккаунтов, телефонных номеров и email-адресов.',
  },
]

export function FaqSection() {
  return (
    <section id="faq" className="py-24 relative">
      <div className="container mx-auto px-4 max-w-3xl">
        <motion.div
          initial={{ opacity: 0, y: 30 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={{ once: true }}
          transition={{ duration: 0.6 }}
          className="text-center mb-16"
        >
          <p className="text-indigo-400 font-semibold text-sm uppercase tracking-widest mb-3">FAQ</p>
          <h2 className="text-4xl md:text-5xl font-bold text-white mb-4">
            Вопросы и ответы
          </h2>
          <p className="text-white/50 text-lg">
            Если не нашли ответ — пишите на GitHub Issues
          </p>
        </motion.div>

        <motion.div
          initial={{ opacity: 0, y: 20 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={{ once: true }}
          transition={{ duration: 0.6, delay: 0.1 }}
          className="rounded-2xl border border-white/10 bg-white/5 backdrop-blur-sm p-6"
        >
          <Accordion type="single" collapsible className="w-full">
            {faqs.map((faq, i) => (
              <AccordionItem key={i} value={`item-${i}`}>
                <AccordionTrigger>{faq.q}</AccordionTrigger>
                <AccordionContent>{faq.a}</AccordionContent>
              </AccordionItem>
            ))}
          </Accordion>
        </motion.div>
      </div>
    </section>
  )
}
