/*<info serverAlias="DBCUST-bodb_licensee" executers="wsv_nap" isFunction="0" isNested="0"></info>*/
USE [bodb_licensee]
GO

ALTER PROCEDURE [dbo].[LA_InvoiceSettingSel]
	 @BillerId	INT = 0
	 , @PayerId	INT = 0
AS
/*  
	 Created: 20150408@Florent
	 Task : Get Inoive setting
	 DB: DBCUST.bodb_Licensee  
   
	 Revisions:
		- 20160808@Bravo: Hosting fees
		- 20161129@Bruce: Add isactive status
		- 20210811@Danny: return more info  AttnName, CompanyName, Address based on ActiveAddress [#FeatureID 158133]
		- 20250327@Eddie: Get view log with products of SabaPlay [RedmineID: #217740]
		- 20250512@Eddie: Enhance SP [RedmineID: #226204]
	 Params:
		+ 0 get all biller
		+ <> 0 specify a biller 
	 Example:
		EXEC dbo.LA_InvoiceSettingSel 123, 14
*/
BEGIN
	SET NOCOUNT ON
	
	DECLARE @BillerNameAbbr NVARCHAR(10) = N'RHL'
	
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
				SELECT ', ' + CASE WHEN b.BillerNameAbbreviation <> @BillerNameAbbr THEN CAST(pp.ProductName AS VARCHAR) ELSE CAST(vw.ProductName AS VARCHAR) END
				FROM dbo.LA_InvoiceSetting ii WITH (NOLOCK)
					INNER JOIN dbo.LA_BillerInfo b WITH (NOLOCK) ON ii.ToPartyId = b.PartyId
					LEFT JOIN dbo.LA_f_Products3rd('') pp ON ii.ProductId = pp.Productid
					LEFT JOIN dbo.vw_SabaPlay_Products vw WITH (NOLOCK) ON vw.ProductId = ii.Productid
				WHERE i.FromPartyId = ii.FromPartyId AND i.ToPartyID = ii.ToPartyID
				  AND ii.InvTypeId = i.InvTypeId
				FOR XML PATH (''))
			  , 1, 2, '') AS ProductList
		, i.ActiveAddress
		, CASE WHEN pd.StatusId=1 THEN 1 ELSE 0 END AS IsActive
		, CASE WHEN i.ActiveAddress = 1 THEN pd.Address1
			   WHEN i.ActiveAddress = 2 THEN pd.Address2 END AS Address
		, CASE WHEN i.ActiveAddress = 1 THEN pd.AttnName
			   WHEN i.ActiveAddress = 2 THEN pd.AttnName2 END AS AttnName
		, CASE WHEN i.ActiveAddress = 1 THEN pd.CompanyName
			   WHEN i.ActiveAddress = 2 THEN pd.CompanyName2 END AS CompanyName
		, b.BillerNameAbbreviation
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
		  END, i.InvTypeId, InvTypeName, i.InvTempId, InvTemplateName, ISNULL(i.BankId, 0), i.ActiveAddress, pd.StatusId,
		  CASE WHEN i.ActiveAddress = 1 THEN pd.Address1
			   WHEN i.ActiveAddress = 2 THEN pd.Address2 END,
		  CASE WHEN i.ActiveAddress = 1 THEN pd.AttnName
			   WHEN i.ActiveAddress = 2 THEN pd.AttnName2 END,
		  CASE WHEN i.ActiveAddress = 1 THEN pd.CompanyName
			   WHEN i.ActiveAddress = 2 THEN pd.CompanyName2 END,
		  b.BillerNameAbbreviation
	ORDER BY BillerName , CASE
			WHEN ISNULL(pd.BrandName, '') != ''
				THEN pd.BrandName
			ELSE p1.PartyName
		  END
END
GO