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

	Param's Explannation: 
*/
BEGIN
	SET NOCOUNT ON;
	
	--#Region Get GroupMinFee header
	SELECT GroupMinFeeID, Name AS GroupName, FromDate, ToDate 
	FROM dbo.LA_GroupMinFeeHeader WITH(NOLOCK)
	WHERE GroupMinFeeID = @GroupMinFeeID
	
	--#Region Get GroupMinFee assignment
	DECLARE @PartyTable AS TABLE(GroupMinFeeID SMALLINT, PartyID INT, PartyName VARCHAR(50), IsPrimary BIT)
	
	INSERT INTO @PartyTable(GroupMinFeeID, PartyID, PartyName, IsPrimary)
	SELECT GroupMinFeeID, 
			p.PartyID, 
			p.PartyName, 
			a.IsPrimary
	FROM dbo.LA_GroupMinFeeAssignment a WITH(NOLOCK)
		INNER JOIN dbo.OAS_Party p WITH(NOLOCK) ON a.PartyID = p.PartyID
	WHERE GroupMinFeeID = @GroupMinFeeID
	
	SELECT GroupMinFeeID, PartyID, PartyName, IsPrimary 
	FROM @PartyTable
	--#Endregion
	
	--#Region Get GroupMinFee detail
	DECLARE @BaseCurrencyTable AS TABLE(CurrencyId INT, CurrencyName VARCHAR(10))
	INSERT	INTO @BaseCurrencyTable(CurrencyId,CurrencyName)
	EXECUTE CustDB.dbo.LA_BaseCurrency_Sel
	
	DECLARE @GroupMinFee AS TABLE(GroupMinFeeID SMALLINT, 
									ProductID INT,
									ProductName VARCHAR(100), 
									CurrencyId INT,
									CurrencyName VARCHAR(20), 
									FromDate DATE, 
									ToDate DATE, 
									MinimumFee MONEY, 
									MinimumFeeTerm NVARCHAR(500))
	
	INSERT INTO @GroupMinFee(GroupMinFeeID, ProductID, ProductName, CurrencyId, CurrencyName, FromDate, ToDate, MinimumFee, MinimumFeeTerm)
	SELECT GroupMinFeeID, d.ProductID, p.ProductName, d.CurrencyId, c.CurrencyName, d.FromDate, d.ToDate, d.MinimumFee, d.MinimumFeeTerm
	FROM dbo.LA_GroupMinFeeDetail d WITH(NOLOCK)
		INNER JOIN LA_f_Products3rd('') p ON p.ProductID = d.ProductId
		INNER JOIN @BaseCurrencyTable c ON c.CurrencyId = d.CurrencyId
	WHERE GroupMinFeeID = @GroupMinFeeID
	
	SELECT GroupMinFeeID, ProductID, ProductName, CurrencyId, CurrencyName, FromDate, ToDate, MinimumFee, MinimumFeeTerm
	FROM @GroupMinFee
	--#Endregion
END
GO
