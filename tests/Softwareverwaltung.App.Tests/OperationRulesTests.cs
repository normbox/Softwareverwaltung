using SoftwareInventory.Helper;

namespace Softwareverwaltung.App.Tests;

/// <summary>Der Helfer führt nur aus, was er kennt: unbekannte oder fehlende Operationen sind Fehler, nie ein leerer Erfolg.</summary>
public sealed class OperationRulesTests
{
    [Theory]
    [InlineData(null, false, false, "HelperNoOperation")]
    [InlineData("", false, false, "HelperNoOperation")]
    [InlineData("GibtEsNicht", false, false, "HelperUnknownOperation")]
    [InlineData("GibtEsNicht", true, true, "HelperUnknownOperation")]
    [InlineData("replacehelpercopy", false, false, "HelperUnknownOperation")]
    [InlineData("ReplaceHelperCopy ", false, false, "HelperUnknownOperation")]
    [InlineData("removeregistryentry", false, false, "HelperUnknownOperation")]
    [InlineData("RemoveRegistryEntry", true, false, "HelperOperationNotCombinable")]
    [InlineData("RemoveRegistryEntry", false, true, "HelperOperationNotCombinable")]
    [InlineData("ReplaceHelperCopy", true, false, "HelperOperationNotCombinable")]
    public void RefusesPlansWithoutAKnownTask(string? operation, bool restorePoint, bool hasFilePath, string code)
    {
        var problem = OperationRules.Check(operation, restorePoint, hasFilePath);
        Assert.NotNull(problem);
        Assert.Equal(code, problem!.Code);
    }

    [Fact]
    public void UnknownOperationNamesTheOperationInTheArguments()
    {
        Assert.Equal(["GibtEsNicht"], OperationRules.Check("GibtEsNicht", false, false)!.Args);
    }

    [Theory]
    [InlineData(null, true, false)]
    [InlineData(null, false, true)]
    [InlineData(null, true, true)]
    [InlineData("ReplaceHelperCopy", false, false)]
    [InlineData("RemoveRegistryEntry", false, false)]
    public void AcceptsAKnownTask(string? operation, bool restorePoint, bool hasFilePath)
    {
        Assert.Null(OperationRules.Check(operation, restorePoint, hasFilePath));
    }

    [Theory]
    [InlineData(null, false, "HelperNoOperation")]
    [InlineData("", false, "HelperNoOperation")]
    [InlineData("ReplaceHelperCopy", true, "HelperUnknownOperation")]
    [InlineData("GibtEsNicht", true, "HelperUnknownOperation")]
    public void BatchStepsAreProgramsOnly(string? operation, bool hasFilePath, string code)
    {
        Assert.Equal(code, OperationRules.CheckStep(operation, hasFilePath)!.Code);
    }

    [Fact]
    public void BatchStepWithAProgramIsAccepted()
    {
        Assert.Null(OperationRules.CheckStep(null, true));
    }

    [Fact]
    public void HelperVersionIsSixSoThatTheModuleCanRefuseHelpersWithoutRemoveRegistryEntry()
    {
        Assert.Equal(6, OperationRules.HelperVersion);
    }
}
