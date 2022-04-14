/*<info serverAlias="DBCUST-bodb_licensee,DBLIC-bodb_licensee,DBBAL-bodb_licensee" selecters="bodbAdminNet" isFunction="1" isNested="1"></info>*/
USE bodb_licensee
GO

ALTER FUNCTION [dbo].[LA_f_Products3rd] (@Products VARCHAR(1000))
RETURNS @tbProducts TABLE (ProductID INT, ProductPrefix VARCHAR(10), ProductName VARCHAR(100), OfferSite TINYINT, EndOfSupportDate DATE)
AS

/*  Created: 20150413@Florent
    Task: Get Products Information
    DB: DBCUST.bodb_Licensee, DBLIC.bodb_licensee, DBBAL-bodb_Licensee
    
	Revisions:
		- 20150413@Florent: Initialize function
		- 20191211@Parsons: Non-peak hour promotion [#119538]
		- 20210816@Sophia: add DBBAL [Redmine: #154300]
		- 20220210@Percy: Return OfferSite, EndOfSupportDate [RedmineID: #163495]
*/

BEGIN   
	IF ISNULL(@Products,'') = ''
	BEGIN
		INSERT INTO @tbProducts(ProductID, ProductPrefix, ProductName, OfferSite, EndOfSupportDate)
		SELECT ProductID, ProductPrefix, ProductName, OfferSite, EndOfSupportDate
		FROM dbo.Product3rd WITH (NOLOCK)
		
		UNION
		
		SELECT 0, 'SB', 'Sportsbook', 0, NULL

	END
	ELSE
	BEGIN
		DECLARE @ProductCodes TABLE (ProductCode VARCHAR(10))
		INSERT INTO @ProductCodes(ProductCode)
		SELECT val FROM dbo.strSplit(@Products, ',')

		IF EXISTS(SELECT TOP 1 1 FROM @ProductCodes WHERE ProductCode = 'SB')
		BEGIN
			INSERT INTO @tbProducts(ProductID, ProductPrefix, ProductName, OfferSite, EndOfSupportDate)
			SELECT 0, 'SB', 'Sportsbook', 0, NULL
		END

		INSERT INTO @tbProducts(ProductID, ProductPrefix, ProductName, OfferSite, EndOfSupportDate)
		SELECT p.ProductId, p.ProductPrefix, p.ProductName, p.OfferSite, p.EndOfSupportDate
		FROM dbo.Product3rd p WITH (NOLOCK)
			INNER JOIN @ProductCodes pc ON pc.ProductCode = p.ProductPrefix
		WHERE p.ProductId <> 0
	END
	
	DELETE @tbProducts WHERE ProductID IS NULL

	RETURN
END
GO