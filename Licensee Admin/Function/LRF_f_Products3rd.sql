/*<info serverAlias="DBLIC-bodb_Licensee,DBCUST-bodb_Licensee" selecters="bodbAdminNet,bodbLicenseeNet" isFunction="1" isNested="1"></info>*/
USE [bodb_licensee]
GO

ALTER FUNCTION [dbo].[LRF_f_Products3rd] (@Products VARCHAR(1000))
	RETURNS @tbProducts TABLE (ProductID INT, InvoiceProductID INT, ProductPrefix VARCHAR(10), ProductName VARCHAR(100))
AS

/*
	Created: 20150129@Florent  
    Task: Get Product Information
	DB: DBLIC.bodb_Licensee, DBCUST.bodb_Licensee
    
	Revisions:
		- 20160915@Jim: hard-code for testing Colossus Bets on UAT
		- 20190702@Amanda: Remove wrong hard-code [RedmineID: #116107]
		- 20220510@Danny: Use String_split built-in function [RemineID: #171831]
*/

BEGIN     
	IF ISNULL(@Products,'') = ''
		RETURN

	IF CHARINDEX( 'SB', @Products) <> 0
	BEGIN
		INSERT INTO @tbProducts(ProductID, ProductPrefix, ProductName)
		SELECT 0, 'SB', 'SportsBook'				
	END

	SELECT @Products = REPLACE(@Products, 'SB','')
	BEGIN
		INSERT INTO @tbProducts(ProductID, ProductPrefix, ProductName)
		SELECT p.Productid, p.ProductPrefix, p.ProductName
		FROM STRING_SPLIT(@Products,',') s
			LEFT JOIN dbo.Product3rd p WITH(NOLOCK) ON s.value = p.ProductPrefix
	END

	UPDATE @tbProducts
	SET InvoiceProductID = ProductID + 1

	DELETE @tbProducts WHERE ProductID IS NULL
	RETURN
END
GO