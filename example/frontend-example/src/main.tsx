import React from 'react'
import ReactDOM from 'react-dom/client'
import { Connect } from '@stacks/connect-react'
import App from './App'
import './index.css'
import { userSession } from './stacks'

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <Connect
      authOptions={{
        appDetails: {
          name: 'Roxy Clicker',
          icon: window.location.origin + '/logo.png',
        },
        redirectTo: '/',
        onFinish: () => {
          window.location.reload();
        },
        userSession,
      }}
    >
      <App />
    </Connect>
  </React.StrictMode>,
)
