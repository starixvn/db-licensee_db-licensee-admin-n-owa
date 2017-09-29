USE [bodb_licensee]
GO

ALTER PROCEDURE [dbo].[LA_Inv_InvoiceTypeInfoGet] 
	  @BillerId INT
	, @PayerId INT	
AS
/*	Header:
	Created: 2015.08.06 - Bravo.Tran
	Task : Create Invoice 
	DB: DB052.bodb_Licensee
   
	Revisions: 
		+ 20150806@Bravo: Invoice Type Info - Get
		+ 20170717@Bruce: show product for type = 1 only [#79905]
*/
/*	Example:
	USE bodb_licensee
	DECLARE @BillerId INT = 98
	DECLARE @PartyId INT = 14
	
	EXEC LA_Inv_InvoiceTypeInfoGet @BillerId, @PartyId
*/
BEGIN
	SET NOCOUNT ON
	
	SELECT	it.InvTypeId		AS InvoiceTypeId, 
			it.InvTypeName		AS InvoiceTypeName, 
			p.ProductPrefix		AS ProductCode,
			p.ProductName		AS ProductName
	FROM	dbo.LA_InvoiceSetting ivs WITH(NOLOCK) 
			INNER JOIN dbo.LA_InvoiceType it WITH(NOLOCK) ON ivs.InvTypeId = it.InvTypeId 
			LEFT JOIN dbo.LA_f_Products3rd('') p ON ivs.ProductId = p.Productid AND it.InvTypeId = 1 -- software & data fee
	WHERE	ivs.FromPartyId = @PayerId AND ivs.ToPartyId = @BillerId
	
END		

GO
GRANT EXECUTE ON [dbo].[LA_Inv_InvoiceTypeInfoGet] TO bodbAdminNet