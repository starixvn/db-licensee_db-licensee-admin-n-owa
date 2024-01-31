/*<info serverAlias="DBLIC-bodb_licensee,DBACC-bodb_licensee" selecters="bodbAdminNet" isFunction="1" isNested="1"></info>*/
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
		- 20190718@Bruce: Integrate CN88 data in LA [#116859]
		- 20200529@Percy: Add condition by productID for get all deposit setting [RedmineID: #134867]
		- 20231225@Danny: Integrate Jollysports group Licensees [RedmineID: #198293]

    Param's Explanation: 
*/  

BEGIN       
    DECLARE @SystemID INT
	
	DECLARE @CreditLicensees AS TABLE(PartyId INT)
	INSERT INTO @CreditLicensees SELECT PartyId FROM dbo.OAS_PartyDetail WITH(NOLOCK) WHERE IsDeposit = 0

    SELECT  @SystemID = id
    FROM    dbo.Systems WITH ( NOLOCK )
    WHERE   SystemName = @System
   
    DECLARE @ProductTable TABLE (ProductID SMALLINT, ProductPrefix VARCHAR(20))  
     
    INSERT  INTO @ProductTable( ProductID, ProductPrefix)
    SELECT  CASE 
				WHEN s.value = 'SB' THEN 0
                ELSE p3.Productid
            END ,
            s.value
    FROM    STRING_SPLIT(@ProductCodes, ',') s
            LEFT JOIN dbo.Product3rd p3 WITH ( NOLOCK ) ON s.value = p3.ProductPrefix	

    INSERT  INTO @tbChargeInfo(ChargeID, PartyID, ProductID, DI_Rate, ChargeType, IsDeposit, Fromdate, Todate, IsParent)
    SELECT  DI.ChargeID ,
            CASE WHEN Di.FromParty IN (SELECT z.PartyID FROM dbo.LA_f_BillingGroupSel() z ) THEN DI.FromParty 
				 WHEN cl.PartyID IS NOT NULL THEN 999 
				 ELSE Di.FromParty END,
            DI.ProductID ,
            DI.Rate ,
            DI.ChargeType ,
			CASE WHEN cl.PartyID IS NOT NULL THEN 0 ELSE 1 END,
            CASE WHEN @FromDate <= DI.FromDate 
					THEN DI.FromDate
                    ELSE @FromDate
            END ,
            CASE WHEN @ToDate >= DI.ToDate 
					THEN DI.ToDate
                    ELSE @ToDate
            END,
			CASE WHEN DI.FromParty IN (SELECT z.PartyID FROM dbo.LA_f_BillingGroupSel() z ) OR cl.PartyID IS NOT NULL THEN 1 ELSE 0 END
    FROM    dbo.OAS_ChargeInfo DI (NOLOCK)
            INNER JOIN dbo.LA_ChargeInfo_SystemMapping cs (NOLOCK) ON DI.ChargeID = cs.ChargeID
                                                    AND cs.SystemID = @SystemID
            INNER JOIN dbo.OAS_Party t (NOLOCK) ON DI.ToParty = t.PartyID
                                                    AND t.PartyType = 3
                                                    AND (t.OldRefID IS NULL OR t.OldRefID IN (2, 3, 5, 6))
			LEFT JOIN @CreditLicensees cl ON cl.PartyID = Di.FromParty
    WHERE   ( @FromDate BETWEEN DI.FromDate AND DI.ToDate
                OR @ToDate BETWEEN DI.FromDate AND DI.ToDate
                OR DI.FromDate BETWEEN @FromDate AND @ToDate
                OR DI.ToDate BETWEEN @FromDate AND @ToDate
            )
            AND DI.ProductID IN ( SELECT ProductID FROM @ProductTable )
            AND NOT EXISTS ( SELECT 1 FROM dbo.OAS_ChargeInfoSub (NOLOCK) WHERE DI.ChargeID = ChargeIdRef )   

	-- Region: Force get all deposit setting(In case of having OW setting only. Ex: AB)
	BEGIN
		;WITH cte_MissingBillingGroupSetting AS
		(
			SELECT PartyID, ProductID
			FROM bodb_licensee.dbo.OAS_Party p WITH (NOLOCK)
				CROSS JOIN @ProductTable pro
			WHERE p.PartyID IN (SELECT z.PartyID FROM dbo.LA_f_BillingGroupSel() z )
				AND NOT EXISTS (SELECT 1 FROM @tbChargeInfo c WHERE c.PartyID = p.PartyID AND c.ProductID = pro.ProductID)
		)
		INSERT INTO @tbChargeInfo(ChargeID, PartyID, ProductID, DI_Rate, ChargeType, IsDeposit, Fromdate, Todate, IsParent)
		SELECT ChargeID, c.PartyID, c.ProductID, DI_Rate, ChargeType, IsDeposit, Fromdate, Todate, IsParent
		FROM cte_MissingBillingGroupSetting c
		INNER JOIN @tbChargeInfo ci ON ci.PartyID = 1 AND c.ProductID = ci.ProductID
	END
	
	-- End-Region: Force get all deposit setting
	RETURN;  
END;
GO