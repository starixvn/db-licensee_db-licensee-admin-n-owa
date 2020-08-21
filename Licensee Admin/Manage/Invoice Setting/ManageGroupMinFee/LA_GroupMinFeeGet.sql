/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="1"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE [dbo].[LA_GroupMinFeeGet]
	@GroupMinFeeID SMALLINT
AS
/*
	Created: 20200701@Happy
	Task : Update GroupMinFee
	DB: DBCUST.bodb_Licensee

	Revisions:
		- 20200701@Happy: Implement Group Min Fee [#134492]

	Param's Explannation: 
*/
BEGIN
	SET NOCOUNT ON;
	
	--#Region LA_GroupMinFeeHeader
	SELECT GroupMinFeeID, [Name] AS GroupName, FromDate, ToDate 
	FROM dbo.LA_GroupMinFeeHeader WITH(NOLOCK)
	WHERE GroupMinFeeID = @GroupMinFeeID
	--#EndRegion LA_GroupMinFeeHeader
	
	--#Region LA_GroupMinFeeAssignment
	SELECT GroupMinFeeID, 
			p.PartyID, 
			p.PartyName, 
			a.IsPrimary
	FROM dbo.LA_GroupMinFeeAssignment a WITH(NOLOCK)
		INNER JOIN dbo.OAS_Party p WITH(NOLOCK) ON a.PartyID = p.PartyID
	WHERE GroupMinFeeID = @GroupMinFeeID
	--#Endregion LA_GroupMinFeeAssignment
	
	--#Region LA_GroupMinFeeDetail
	DECLARE @BaseCurrencyTable TABLE(CurrencyId INT, CurrencyName VARCHAR(10))
	INSERT	INTO @BaseCurrencyTable(CurrencyId,CurrencyName)
	EXECUTE CustDB.dbo.LA_BaseCurrency_Sel
	
	SELECT GroupMinFeeID, d.ProductID, p.ProductName, d.CurrencyId, c.CurrencyName, d.FromDate, d.ToDate, d.MinimumFee, d.MinimumFeeTerm
	FROM dbo.LA_GroupMinFeeDetail d WITH(NOLOCK)
		INNER JOIN LA_f_Products3rd('') p ON p.ProductID = d.ProductId
		INNER JOIN @BaseCurrencyTable c ON c.CurrencyId = d.CurrencyId
	WHERE GroupMinFeeID = @GroupMinFeeID
	--#Endregion LA_GroupMinFeeDetail
END
GO