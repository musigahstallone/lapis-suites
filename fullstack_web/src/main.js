import { createApp } from 'vue'
import App from './App.vue'
import router from './router'
import { initSSE } from './sse'
import './styles.css'
import './forms.css'

initSSE()

const app = createApp(App)
app.use(router)
app.mount('#app')
