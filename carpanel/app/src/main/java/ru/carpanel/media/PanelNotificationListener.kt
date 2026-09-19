package ru.carpanel.media

import android.service.notification.NotificationListenerService

/**
 * Служба-пустышка.
 *
 * Сама она ничего не делает, но её наличие даёт системе повод выдать
 * разрешение «доступ к уведомлениям». Только с ним Android отдаёт список
 * работающих проигрывателей, а значит — кнопки «дальше» и «пауза»
 * для Яндекс Музыки и любого другого плеера.
 */
class PanelNotificationListener : NotificationListenerService()
