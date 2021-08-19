/*<info serverAlias="DBCUST-bodb_licensee,DBLIC-bodb_licensee,DBBAL-bodb_licensee" selecters="bodbAdminNet" isFunction="1" isNested="1"></info>*/
USE bodb_licensee
GO

ALTER FUNCTION [dbo].[LA_f_Products3rd] (@Products VARCHAR(1000))
RETURNS @tbProducts TABLE (ProductID INT, ProductPrefix VARCHAR(10), ProductName VARCHAR(100))
AS

/*  Created: 20150413@Florent
    Task: Get Products Information
    DB: DBCUST.bodb_Licensee, DBLIC.bodb_licensee
    
	Revisions:
		- 20150413@Florent: Initialize function
		- 20191211@Parsons: Non-peak hour promotion [#119538]
		- 20210816@Sophia: add DBBAL [Redmine: #154300]
*/

BEGIN   
	IF ISNULL(@Products,'') = ''
	BEGIN
		INSERT INTO @tbProducts(ProductID, ProductPrefix, ProductName)
		SELECT ProductID, ProductPrefix, ProductName 
		FROM dbo.Product3rd WITH (NOLOCK)
		
		UNION
		
		SELECT 0, 'SB', 'Sportsbook'

	END
	ELSE
	BEGIN
		DECLARE @ProductCodes TABLE (ProductCode VARCHAR(10))
		INSERT INTO @ProductCodes(ProductCode)
		SELECT val FROM dbo.strSplit(@Products, ',')

		IF EXISTS(SELECT TOP 1 1 FROM @ProductCodes WHERE ProductCode = 'SB')
		BEGIN
			INSERT INTO @tbProducts(ProductID, ProductPrefix, ProductName)
			SELECT 0, 'SB', 'Sportsbook'				
		END

		INSERT INTO @tbProducts(ProductID, ProductPrefix, ProductName)
		SELECT ProductID, ProductPrefix, ProductName 
		FROM dbo.Product3rd WITH (NOLOCK)
			INNER JOIN @ProductCodes ON ProductCode = ProductPrefix
		WHERE ProductId <> 0
	END
	
	DELETE @tbProducts WHERE ProductID IS NULL

	RETURN
END
GO