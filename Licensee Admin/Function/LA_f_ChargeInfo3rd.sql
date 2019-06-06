/*<info serverAlias="DBLIC-bodb_licensee,DBACC-bodb_licensee" selecters="bodbAdminNet" isFunction="1" isNested="1"></info>*/
USE bodb_licensee
GO

ALTER FUNCTION [dbo].[LA_f_ChargeInfo3rd]
    (
      @FromDate DATETIME ,
      @ToDate DATETIME ,
      @ProductCodes VARCHAR(1000) ,
      @System VARCHAR(10) = 'OA'
    )
RETURNS @tbChargeInfo TABLE
    (
      ChargeID INT ,
      PartyID INT ,      
      ProductID INT ,
      DI_Rate MONEY ,
      ChargeType INT ,
	  IsDeposit INT,
      Fromdate SMALLDATETIME ,
      Todate SMALLDATETIME,
	  IsParent BIT
    )
AS 

/*  
	Created: 20170310@Harper  
    Task: Get Charge Information of Product 3rd  
    DB:   DBLIC.bodb_Licensee    
	
	Revisions:  
		- 20180122@Harper: Fix return data rows [RedmineID: #89006]
		- 20180302@Harper: Inspired , Lupine, Star Express, AG is 3rd Licensee [#RedmineID: #91255]
		- 20180327@Harper: Add more Cozni as Parent Licensee [RedmineID: #85681]
		- 20180508@Harper: Change PayToSupplier term of Exchange product [RedmineID: #94281]
		- 20180716@bruce: add new group TEST for credit [#98126]
		
    Param's Explanation: 
*/  

BEGIN       
    DECLARE @SystemID INT
	DECLARE @tmpCompany	AS TABLE (ID INT IDENTITY, PartyID INT)

    SELECT  @SystemID = id
    FROM    dbo.Systems WITH ( NOLOCK )
    WHERE   SystemName = @System
   
    DECLARE @ProductTable TABLE (ProductID SMALLINT, ProductPrefix VARCHAR(20))  
     
    INSERT  INTO @ProductTable( ProductID, ProductPrefix)
    SELECT  CASE 
				WHEN s.val = 'SB' THEN 0
                ELSE p3.Productid
            END ,
            s.val
    FROM    bodb02.dbo.strSplit(@ProductCodes, ',') s
            LEFT JOIN dbo.Product3rd p3 WITH ( NOLOCK ) ON s.val = p3.ProductPrefix	

    INSERT  INTO @tbChargeInfo
								( ChargeID ,
									PartyID ,
									ProductID ,
									DI_Rate ,
									ChargeType ,
									IsDeposit,
									Fromdate ,
									Todate,
									IsParent
								)
    SELECT  DI.ChargeID ,
            CASE WHEN Di.FromParty IN (1, 11, 98, 9) THEN DI.FromParty 
				 WHEN Di.FromParty IN (25, 30, 324) THEN 999 
				 ELSE Di. FromParty END,
            DI.ProductID ,
            DI.Rate ,
            DI.ChargeType ,
			CASE WHEN Di.FromParty IN (25, 30, 324) THEN 0 ELSE 1 END,
            CASE WHEN @FromDate <= DI.FromDate 
					THEN DI.FromDate
                    ELSE @FromDate
            END ,
            CASE WHEN @ToDate >= DI.ToDate 
					THEN DI.ToDate
                    ELSE @ToDate
            END,
			CASE WHEN DI.FromParty IN (1, 11, 98, 9, 25, 30, 324) THEN 1 ELSE 0 END
    FROM    dbo.OAS_ChargeInfo DI (NOLOCK)
            INNER JOIN dbo.LA_ChargeInfo_SystemMapping cs (NOLOCK) ON DI.ChargeID = cs.ChargeID
                                                    AND cs.SystemID = @SystemID
            INNER JOIN dbo.OAS_Party t (NOLOCK) ON DI.ToParty = t.PartyID
                                                    AND t.PartyType = 3
                                                    AND (t.OldRefID IS NULL OR t.OldRefID IN (2, 3, 5, 6))
    WHERE   ( @FromDate BETWEEN DI.FromDate AND DI.ToDate
                OR @ToDate BETWEEN DI.FromDate AND DI.ToDate
                OR DI.FromDate BETWEEN @FromDate AND @ToDate
                OR DI.ToDate BETWEEN @FromDate AND @ToDate
            )
            AND DI.ProductID IN ( SELECT ProductID FROM @ProductTable )
            AND NOT EXISTS ( SELECT 1 FROM dbo.OAS_ChargeInfoSub (NOLOCK) WHERE DI.ChargeID = ChargeIdRef )   


	DECLARE @PartyID INT, @n INT, @m INT

	INSERT INTO @tmpCompany (PartyID)
	SELECT PartyID
	FROM bodb_licensee.dbo.OAS_Party p WITH (NOLOCK)
	WHERE PartyName IN ('ONEWorks','Boping', 'Zelianta', 'Cozni')
		AND NOT EXISTS (SELECT 1 FROM @tbChargeInfo WHERE PartyID = p.PartyID)

	SELECT @n = 1
		  ,@m = MAX(ID) FROM @tmpCompany
	
	WHILE (@n <= @m)	  
	BEGIN
		SELECT @PartyID = PartyID FROM @tmpCompany WHERE ID = @n
		INSERT INTO @tbChargeInfo
		        ( ChargeID ,
		          PartyID ,
		          ProductID ,
		          DI_Rate ,
		          ChargeType ,
		          IsDeposit ,
		          Fromdate ,
		          Todate,
				  IsParent
		        )
		SELECT ChargeID, @PartyID, ProductID, DI_Rate, ChargeType, IsDeposit, Fromdate, Todate, IsParent
		FROM @tbChargeInfo
		WHERE PartyID = 1
		
		SET @n = @n + 1 	
	END

   RETURN;  
END;
GO