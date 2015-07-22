USE [bodb_licensee]
GO
/****** Object:  StoredProcedure [dbo].[LA_Inv_InvoiceTypeInfoGet]   Script Date: 07/21/2015 09:12:41 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[LA_Inv_InvoiceTypeInfoGet] 
	  @BillerId INT
	, @PayerId INT	
WITH RECOMPILE
AS
SET NOCOUNT ON
BEGIN
	SELECT it.InvTypeId AS InvoiceTypeId, it.InvTypeName AS InvoiceTypeName, 
		CASE 
			WHEN ivs.ProductId = 0 THEN 'SB' 
			ELSE p.ProductPrefix
			END AS ProductCode,
		CASE 
			WHEN ivs.ProductId = 0 THEN 'Sportbooks' 
			ELSE p.ProductName
			END AS ProductName
	FROM dbo.LA_InvoiceSetting ivs WITH(NOLOCK) INNER JOIN dbo.LA_InvoiceType it WITH(NOLOCK) ON ivs.InvTypeId = it.InvTypeId 
		LEFT JOIN bodb_licensee.dbo.Product3rd p WITH(NOLOCK) ON ivs.ProductId = p.Productid
	WHERE	ivs.FromPartyId = @PayerId 
			AND ivs.ToPartyId = @BillerId	
END