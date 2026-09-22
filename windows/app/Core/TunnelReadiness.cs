using System;
using System.Text.Json;

namespace QPVPN.Core;

/// <summary>
/// Разбор ответа службы туннеля: поднялся он уже или ещё нет.
///
/// Вынесено отдельно, потому что от этого ответа зависит всё остальное.
/// Пока программа считала запущенную службу готовым туннелем, она
/// проверяла связь раньше, чем та появлялась, не получала её и уходила
/// перенастраивать туннель по кругу — так и не дав ему подняться.
/// </summary>
public static class TunnelReadiness
{
    /// <summary>Что служба рассказала о себе.</summary>
    public readonly record struct Report(bool Running, long Handshake, long RxBytes, long TxBytes)
    {
        /// <summary>
        /// Туннель работает: служба запущена и сервер ответил.
        ///
        /// Приветствие от сервера — единственный надёжный признак. Служба
        /// может быть запущена, адаптер создан, маршруты проложены — и всё
        /// это без единого ответа с той стороны.
        /// </summary>
        public bool IsReady => Running && Handshake > 0;
    }

    /// <summary>
    /// Читает строку, которую печатает служба. Непонятный ответ — не готов.
    /// </summary>
    public static Report Parse(string json)
    {
        if (string.IsNullOrWhiteSpace(json)) return default;

        try
        {
            using var document = JsonDocument.Parse(json);
            var root = document.RootElement;
            if (root.ValueKind != JsonValueKind.Object) return default;

            return new Report(
                Running: root.TryGetProperty("running", out var running)
                    && running.ValueKind == JsonValueKind.True,
                Handshake: Number(root, "lastHandshake"),
                RxBytes: Number(root, "rxBytes"),
                TxBytes: Number(root, "txBytes"));
        }
        catch (JsonException)
        {
            // Служба ещё поднимается и отвечает не полностью.
            return default;
        }
    }

    private static long Number(JsonElement root, string name) =>
        root.TryGetProperty(name, out var value)
        && value.ValueKind == JsonValueKind.Number
        && value.TryGetInt64(out var number)
            ? number
            : 0;
}
