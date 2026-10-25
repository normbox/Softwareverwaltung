@{
    ExcludeRules = @(
        # PowerShell 7 liest UTF-8 ohne BOM korrekt; Windows PowerShell 5.1 wird nicht unterstützt.
        # Ausnahme: Der erhöhte Helfer (Elevated/) läuft auch unter 5.1 und ist mit BOM gespeichert.
        'PSUseBOMForUnicodeEncodedFile'
        # New-*-Funktionen im Modul erzeugen nur Objekte im Speicher und ändern keinen Systemzustand.
        'PSUseShouldProcessForStateChangingFunctions'
    )
}
