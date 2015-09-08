USE [bodb_licensee]
GO
/****** Object:  StoredProcedure [dbo].[LA_Inv_InvoiceTypeInfoGet]   Script Date: 07/21/2015 09:12:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
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
		+ 2015.08.06: Invoice Type Info - Get
*/
/*	Example:
	USE bodb_licensee
	DECLARE @BillerId INT = 98
	DECLARE @PartyId INT = 14
	
	EXEC LA_Inv_InvoiceTypeInfoGet @BillerId, @PartyId
*/
BEGIN
	SET NOCOUNT ON
	
	SELECT	it.InvTypeId AS InvoiceTypeId, 
			it.InvTypeName AS InvoiceTypeName, 
			CASE 
				WHEN ivs.ProductId = 0 THEN 'SB' 
				ELSE p.ProductPrefix
			END AS ProductCode,
			CASE 
				WHEN ivs.ProductId = 0 THEN 'Sportsbook' 
				ELSE p.ProductName
			END AS ProductName
	FROM	dbo.LA_InvoiceSetting ivs WITH(NOLOCK) 
			INNER JOIN dbo.LA_InvoiceType it WITH(NOLOCK) ON ivs.InvTypeId = it.InvTypeId 
			LEFT JOIN bodb_licensee.dbo.Product3rd p WITH(NOLOCK) ON ivs.ProductId = p.Productid
	WHERE	ivs.FromPartyId = @PayerId 
			AND ivs.ToPartyId = @BillerId
	
END		

GO
GRANT EXECUTE ON [dbo].[LA_Inv_InvoiceTypeInfoGet] TO bodbAdminNet