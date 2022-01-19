/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="1"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE [dbo].[LA_GroupMinFeeGet]
	@GroupMinFeeID SMALLINT
AS
/*
	Created: 20200701@Happy
	Task : Update GroupMinFee
	DB: DBLIC.bodb_Licensee

	Revisions:
		- 20200701@Happy: Implement Group Min Fee [#134492]
		- 20210824@Danny: get licensee status from OIC And Relocate SP  [#167637]

	Param's Explannation: 
		OIC LicenseeStatusId: 
				1	Up Coming
				2	Soft Launch
				3	Active
				4	Terminated
				5	Cancelled
				6	Suspended
				999 Unrecognized
*/
BEGIN
	SET NOCOUNT ON;

	CREATE TABLE #tmp_licenseeOIC (RegisteredLicenseeName NVARCHAR(50), LicenseeStatusId INT)
	INSERT INTO #tmp_licenseeOIC(RegisteredLicenseeName, LicenseeStatusId)
	SELECT	RegisteredLicenseeName, LicenseeStatusId
	FROM	DBOIC.bodb_OIC.dbo.licensee WITH(NOLOCK) 
	
	--#Region LA_GroupMinFeeHeader
	SELECT GroupMinFeeID, [Name] AS GroupName, FromDate, ToDate 
	FROM dbo.LA_GroupMinFeeHeader WITH(NOLOCK)
	WHERE GroupMinFeeID = @GroupMinFeeID
	--#EndRegion LA_GroupMinFeeHeader
	
	--#Region LA_GroupMinFeeAssignment
	SELECT GroupMinFeeID, 
			p.PartyID, 
			p.PartyName, 
			a.IsPrimary,
			oic.LicenseeStatusId
	FROM dbo.LA_GroupMinFeeAssignment a WITH(NOLOCK)
		INNER JOIN dbo.OAS_Party p WITH(NOLOCK) ON a.PartyID = p.PartyID
		INNER JOIN  dbo.Licensees l WITH(NOLOCK) ON l.LicenseeID = p.OldRefID
		INNER JOIN	#tmp_licenseeOIC oic WITH(NOLOCK) ON oic.RegisteredLicenseeName = l.LicenseeName
	WHERE GroupMinFeeID = @GroupMinFeeID
	--#Endregion LA_GroupMinFeeAssignment
	
	--#Region LA_GroupMinFeeDetail
	DECLARE @BaseCurrencyTable TABLE(CurrencyId INT, CurrencyName VARCHAR(10))
	INSERT	INTO @BaseCurrencyTable(CurrencyId,CurrencyName)
	EXECUTE dbo.LA_SelBaseCurrency
	
	SELECT GroupMinFeeID, d.ProductID, p.ProductName, d.CurrencyId, c.CurrencyName, d.FromDate, d.ToDate, d.MinimumFee, d.MinimumFeeTerm
	FROM dbo.LA_GroupMinFeeDetail d WITH(NOLOCK)
		INNER JOIN LA_f_Products3rd('') p ON p.ProductID = d.ProductId
		INNER JOIN @BaseCurrencyTable c ON c.CurrencyId = d.CurrencyId
	WHERE GroupMinFeeID = @GroupMinFeeID
	--#Endregion LA_GroupMinFeeDetail


	DROP TABLE #tmp_licenseeOIC
END
GO