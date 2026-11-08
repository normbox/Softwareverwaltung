@{
    ExcludeRules = @(
        # PowerShell 7 liest UTF-8 ohne BOM korrekt; Windows PowerShell 5.1 wird nicht unterstützt.
        'PSUseBOMForUnicodeEncodedFile'
        # New-*-Funktionen im Modul erzeugen nur Objekte im Speicher und ändern keinen Systemzustand.
        'PSUseShouldProcessForStateChangingFunctions'
    )
}
