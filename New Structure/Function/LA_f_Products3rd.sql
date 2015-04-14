USE [bodb_licensee]
GO
/****** Object:  UserDefinedFunction [dbo].[LA_f_Products3rd]    Script Date: 14/04/2015 10:34:37 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER FUNCTION [dbo].[LA_f_Products3rd] (@Products VARCHAR(1000))
RETURNS @tbProducts TABLE (ProductID INT, ProductPrefix VARCHAR(10), ProductName VARCHAR(100))
AS
/*  Created: 20150413@Florent  
    Task : Get Products Information
    DB: DB052/bodb_Licensee  
    Param's Explanation:       
	select * FROM dbo.LRF_f_Products3rd('NG,SB')
*/

BEGIN   
	DECLARE @ProductsID AS TABLE (ProductID TINYINT, ProductPrefix VARCHAR(10), ProductName VARCHAR(50))
	BEGIN  
		INSERT INTO @ProductsID(ProductID, ProductPrefix, ProductName)  
		SELECT ProductID, ProductPrefix, ProductName 
		FROM dbo.Product3rd WITH (NOLOCK)
		UNION
		SELECT 0, 'SB', 'Sportbooks'			
	END

	IF ISNULL(@Products,'') = ''
	BEGIN
		INSERT INTO @tbProducts(ProductID, ProductPrefix, ProductName)
			SELECT Productid, ProductPrefix, ProductName
			FROM @ProductsID 
	END
	ELSE
	BEGIN		
		IF CHARINDEX( 'SB', @Products) <> 0
		BEGIN
			INSERT INTO @tbProducts(ProductID, ProductPrefix, ProductName)
			SELECT 0, 'SB', 'SportsBook'				
		END

		SELECT @Products = REPLACE(@Products, 'SB','')
		BEGIN
			INSERT INTO @tbProducts(ProductID, ProductPrefix, ProductName)
			SELECT p.Productid, p.ProductPrefix, p.ProductName
			FROM dbo.strSplit(@Products,',') s
				INNER JOIN @ProductsID p ON s.val = p.ProductPrefix
		END
	END

	DELETE @tbProducts WHERE ProductID IS NULL
	RETURN
END
GO
GRANT VIEW DEFINITION ON [dbo].[LA_f_Products3rd] TO [vnteam] 
GRANT EXECUTE ON [dbo].[LA_f_Products3rd] TO bodbAdminNet 