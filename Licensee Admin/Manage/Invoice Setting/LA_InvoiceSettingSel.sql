USE [bodb_licensee]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[LA_InvoiceSettingSel]
	 @BillerId	INT	= 0		 
	 , @PayerId	INT = 0
AS
/*  
	 Created: 20150408@Florent
	 Task : Get Inoive setting
	 DB: DB052.bodb_Licensee  
   
	 Revisions:     		  
	 Params:
		+ 0 get all biller
		+ <> 0 specify a biller 
	 Example:
		EXEC dbo.LA_InvoiceSettingSel 123, 14
*/
BEGIN
	SET NOCOUNT ON
	SELECT ToPartyID			AS BillerId
		, BillerName			AS BillerName
		, FromPartyId			AS PayerId
		, ISNULL(i.BankId, 0)	AS BankId
		, CASE 
			WHEN ISNULL(pd.BrandName, '') != '' 
				THEN pd.BrandName 
			ELSE p1.PartyName 
		  END					AS PayerName
		, i.InvTypeId			AS InvoiceTypeId
		, InvTypeName			AS InvoiceTypeName
		, i.InvTempId			AS InvoiceTempId
		, InvTemplateName		AS InvoiceTemplateName
		, COUNT(i.ProductId)	AS NumberOfProduct
		, STUFF((
				SELECT ', ' + CAST(pp.ProductName AS VARCHAR)
				FROM dbo.LA_InvoiceSetting ii WITH (NOLOCK)
					LEFT JOIN dbo.LA_f_Products3rd('') pp ON ii.ProductId = pp.Productid
				WHERE i.FromPartyId = ii.FromPartyId AND i.ToPartyID = ii.ToPartyID
					AND ii.InvTypeId = i.InvTypeId
				FOR XML PATH (''))
			  , 1, 2, '') AS ProductList
	FROM dbo.OAS_Party p WITH (NOLOCK)
		INNER JOIN dbo.LA_BillerInfo b WITH (NOLOCK) ON p.PartyID = b.PartyID		
		INNER JOIN dbo.LA_InvoiceSetting i WITH (NOLOCK) ON i.ToPartyId = p.PartyID
		LEFT JOIN dbo.OAS_Party p1 WITH (NOLOCK) ON i.FromPartyId = p1.PartyID
		LEFT JOIN dbo.OAS_PartyDetail pd WITH (NOLOCK) ON p1.PartyID = pd.PartyID
		LEFT JOIN dbo.LA_InvoiceTemplate temp WITH (NOLOCK) ON i.InvTempId = temp.InvTemplateId
		LEFT JOIN dbo.LA_InvoiceType tp WITH (NOLOCK) ON i.InvTypeId = tp.InvTypeId
	WHERE p.PartyType = 4 
		AND (@BillerId = 0 OR i.ToPartyId = @BillerId)
		AND (@PayerId = 0 OR i.FromPartyId = @PayerId)
	GROUP BY ToPartyID, BillerName, FromPartyId, CASE 
			WHEN ISNULL(pd.BrandName, '') != '' 
				THEN pd.BrandName 
			ELSE p1.PartyName 
		  END, i.InvTypeId, InvTypeName, i.InvTempId, InvTemplateName, ISNULL(i.BankId, 0)
	ORDER BY BillerName , CASE 
			WHEN ISNULL(pd.BrandName, '') != '' 
				THEN pd.BrandName 
			ELSE p1.PartyName 
		  END	
END			 	


GO
GRANT VIEW DEFINITION ON [dbo].[LA_InvoiceSettingSel] TO [vnteam] 
GRANT EXECUTE ON [dbo].[LA_InvoiceSettingSel] TO bodbAdminNet 