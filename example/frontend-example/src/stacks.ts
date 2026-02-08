import { AppConfig, UserSession, showConnect } from '@stacks/connect';
import { STACKS_MOCKNET } from '@stacks/network';

const appConfig = new AppConfig(['store_write', 'publish_data']);
export const userSession = new UserSession({ appConfig });

export const network = STACKS_MOCKNET;

export const authenticate = () => {
    showConnect({
        appDetails: {
            name: 'Roxy Clicker',
            icon: window.location.origin + '/logo.png',
        },
        redirectTo: '/',
        onFinish: () => {
            window.location.reload();
        },
        userSession,
    });
};

export const logout = () => {
    userSession.signUserOut();
    window.location.reload();
};
