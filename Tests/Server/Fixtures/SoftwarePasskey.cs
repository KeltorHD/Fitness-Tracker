using System.Buffers.Binary;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.AspNetCore.WebUtilities;

namespace FitLife.Server.Tests;

/// <summary>Тестовый WebAuthn-аутентификатор: создаёт реальные ES256 attestation/assertion для проверки Identity.</summary>
internal sealed class SoftwarePasskey : IDisposable
{
    private readonly ECDsa _key = ECDsa.Create(ECCurve.NamedCurves.nistP256);
    private readonly byte[] _id = RandomNumberGenerator.GetBytes(32);
    private byte[] _userHandle = [];

    /// <summary>Формирует attestation none с публичным COSE-ключом и подтверждением пользователя.</summary>
    internal string Create(JsonElement options, string origin = "https://localhost", bool userVerified = true)
    {
        _userHandle = WebEncoders.Base64UrlDecode(options.GetProperty("user").GetProperty("id").GetString()!);
        var parameters = _key.ExportParameters(false);
        byte[] cose = [0xa5, 0x01, 0x02, 0x03, 0x26, 0x20, 0x01, 0x21, 0x58, 0x20, .. parameters.Q.X!, 0x22, 0x58, 0x20, .. parameters.Q.Y!];
        var rp = options.GetProperty("rp").GetProperty("id").GetString()!;
        byte[] auth = [.. SHA256.HashData(Encoding.UTF8.GetBytes(rp)), (byte)(userVerified ? 0x45 : 0x41),
            0, 0, 0, 0, .. new byte[16], 0, (byte)_id.Length, .. _id, .. cose];
        // CBOR map: fmt=none, attStmt={}, authData=bytes; только тестовые данные без стороннего пакета.
        byte[] attestation = [0xa3, 0x63, .. "fmt"u8.ToArray(), 0x64, .. "none"u8.ToArray(),
            0x67, .. "attStmt"u8.ToArray(), 0xa0, 0x68, .. "authData"u8.ToArray(), 0x58, (byte)auth.Length, .. auth];
        return JsonSerializer.Serialize(new
        {
            id = WebEncoders.Base64UrlEncode(_id),
            rawId = WebEncoders.Base64UrlEncode(_id),
            type = "public-key",
            response = new
            {
                clientDataJSON = ClientData(options, "webauthn.create", origin),
                attestationObject = WebEncoders.Base64UrlEncode(attestation),
                transports = new[] { "internal" }
            },
            clientExtensionResults = new { }
        });
    }

    /// <summary>Подписывает challenge своим приватным ключом; можно проверить неверный origin, UV или подпись.</summary>
    internal string Assert(JsonElement options, string rp = "localhost", string origin = "https://localhost",
        bool userVerified = true, bool corruptSignature = false, uint counter = 1)
    {
        var count = new byte[4];
        BinaryPrimitives.WriteUInt32BigEndian(count, counter);
        byte[] auth = [.. SHA256.HashData(Encoding.UTF8.GetBytes(rp)), (byte)(userVerified ? 0x05 : 0x01), .. count];
        var client = ClientData(options, "webauthn.get", origin);
        byte[] data = [.. auth, .. SHA256.HashData(WebEncoders.Base64UrlDecode(client))];
        var signature = _key.SignData(data, HashAlgorithmName.SHA256, DSASignatureFormat.Rfc3279DerSequence);
        if (corruptSignature) signature[^1] ^= 1;
        return JsonSerializer.Serialize(new
        {
            id = WebEncoders.Base64UrlEncode(_id),
            rawId = WebEncoders.Base64UrlEncode(_id),
            type = "public-key",
            response = new
            {
                clientDataJSON = client,
                authenticatorData = WebEncoders.Base64UrlEncode(auth),
                signature = WebEncoders.Base64UrlEncode(signature),
                userHandle = WebEncoders.Base64UrlEncode(_userHandle)
            },
            clientExtensionResults = new { }
        });
    }

    /// <summary>Кодирует стандартные client data браузера с challenge из ответа сервера.</summary>
    private static string ClientData(JsonElement options, string type, string origin) =>
        WebEncoders.Base64UrlEncode(JsonSerializer.SerializeToUtf8Bytes(new
        { type, challenge = options.GetProperty("challenge").GetString(), origin, crossOrigin = false }));

    /// <summary>Освобождает тестовый приватный ключ.</summary>
    public void Dispose() => _key.Dispose();
}
