/*<info serverAlias="DBCUST-bodb_licensee" executers="wsv_nap" isFunction="0" isNested="0"></info>*/
USE [bodb_licensee]
GO

ALTER PROCEDURE [dbo].[LA_Inv_InvoiceTypeInfoGet] 
	  @BillerId INT
	, @PayerId INT	
AS
/*	Header:
	Created: 2015.08.06 - Bravo.Tran
	Task : Create Invoice 
	DB: DBCUST.bodb_Licensee
   
	Revisions: 
		- 20150806@Bravo: Invoice Type Info - Get
		- 20170717@Bruce: show product for type = 1 only [#79905]
		- 20250402@Danny: Number Game promotion [RedmineID: #219671]
		- 20250417@Danny: Support billing SabaPlay licensees [RedmineID: #224104]
		- 20250512@Eddie: Enhance SP [RedmineID: #226204]
*/

/*	Example:
	USE bodb_licensee
	DECLARE @BillerId INT = 98
	DECLARE @PartyId INT = 14
	
	EXEC LA_Inv_InvoiceTypeInfoGet @BillerId, @PartyId
*/
BEGIN
	SET NOCOUNT ON

	DECLARE @IsSabaPlayBiller BIT
	
	SELECT @IsSabaPlayBiller = CASE WHEN BillerNameAbbreviation = N'RHL' THEN 1 ELSE 0 END
	FROM LA_BillerInfo WITH(NOLOCK)
	WHERE PartyId = @BillerId 

	DECLARE @data TABLE (InvoiceTypeId SMALLINT, InvoiceTypeName VARCHAR(50), ProductID INT ,ProductCode VARCHAR(10), ProductName VARCHAR(50), OrderNo INT)
	
	INSERT INTO @data (InvoiceTypeId, InvoiceTypeName, ProductID, ProductCode, ProductName, OrderNo)
	SELECT	it.InvTypeId  AS InvoiceTypeId, 
			it.InvTypeName		AS InvoiceTypeName, 
			ivs.ProductID			AS ProductID,
			CASE WHEN @IsSabaPlayBiller = 0 THEN p.ProductPrefix ELSE NULL END	AS ProductCode,
			CASE WHEN @IsSabaPlayBiller = 0 THEN p.ProductName	ELSE sp.ProductName END	AS ProductName,
			p.ProductID * 10	AS OrderNo
	FROM	dbo.LA_InvoiceSetting ivs WITH(NOLOCK) 
			INNER JOIN dbo.LA_InvoiceType it WITH(NOLOCK) ON ivs.InvTypeId = it.InvTypeId 
			LEFT JOIN dbo.LA_f_Products3rd('') p ON ivs.ProductId = p.Productid AND it.InvTypeId = 1 AND @IsSabaPlayBiller = 0 -- software & data fee 
			LEFT JOIN DBLIC.bodb_licenseeReport.dbo.SabaPlay_Products sp  WITH(NOLOCK) ON ivs.ProductId = sp.Productid AND it.InvTypeId = 1 AND @IsSabaPlayBiller =1 
	WHERE	ivs.FromPartyId = @PayerId AND ivs.ToPartyId = @BillerId


	IF EXISTS (SELECT TOP 1 1 FROM @data WHERE InvoiceTypeId = 1 AND ProductID > 0) AND @IsSabaPlayBiller = 0
		INSERT INTO @data (InvoiceTypeId, InvoiceTypeName, ProductID, ProductCode, ProductName, OrderNo)
		SELECT 1, 'Software Data & Licensing Fees', -37, 'SPR(CS)', 'Non-Sportsbook Promotion', 1

	SELECT 	InvoiceTypeId, 
			InvoiceTypeName, 
			ProductID,
			ProductCode,
			ProductName
	FROM	@data
	ORDER BY InvoiceTypeId, OrderNo
END		
GO