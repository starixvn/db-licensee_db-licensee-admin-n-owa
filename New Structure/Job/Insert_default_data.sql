-------*****INSERT Data******-------------
--User
TRUNCATE Table LA_User
INSERT INTO LA_User (GroupID,Username,UserPwd,DisplayName,UserSalt,StatusID,Creator,CreatedDate,ModifiedDate)
SELECT 1,'User_IT','06C5CA94D7C2588B467206F20DFADDC543D54C4E','User IT','CJgH/18v96/w4YAocA==',1,1,GETDATE(),GETDATE()
UNION
SELECT 2,'User_Admin','B12A1ADC414901E19FD321EE7134B2E0EE23C53C','User Admin','+/lMlQTt+grL63qhnw==',1,1,GETDATE(),GETDATE()
UNION
SELECT 3,'User_Normal','2EFDBED0E7BA3D48A017087FEDD3A6C74D262920','User Normal','svR9T+hBYlKIs2BzkQ==',1,1,GETDATE(),GETDATE()

--Function
TRUNCATE TABLE LA_Function
SET IDENTITY_INSERT [dbo].[LA_Function] ON 
GO
INSERT [dbo].[LA_Function] ([FunctionID], [FunctionName], [FunctionDesc], [ParentID], [ParentName], [URL], [CreatedDate], [ModifiedDate], [DisplayOrder], [Creator], [StatusID], [FunctionKey]) 
VALUES (1, N'Administration', N'Administration', 0, N'None', N'', CAST(0x00009F7A01210128 AS DateTime), CAST(0x0000A38B00DA74B2 AS DateTime), 10, 1, 1, N'Administration'),
(2, N'Manage Group', N'Manage Group', 1, N'Administration', N'/Group/ManageGroup', CAST(0x00009F5C00000000 AS DateTime), CAST(0x00009F5C00000000 AS DateTime), 10, 1, 0, N'ManageGroup'),
(3, N'Manage User', N'Manage User', 1, N'Administration', N'/User/ManageUser', CAST(0x00009F5C00000000 AS DateTime), CAST(0x00009F5C00000000 AS DateTime), 20, 1, 1, N'ManageUser'),
(4, N'Total Transaction', N'Total Transaction Report', 0, N'None', N'/TotalTrans/Main', CAST(0x00009F5C00000000 AS DateTime), CAST(0x0000A3C5000EFB9F AS DateTime), 20, 1, 1, N'TotalTransaction'),
(5, N'Win Loss Report', N'Win Loss Report', 0, N'None', N'/Report/WinLoss', CAST(0x00009F5C00000000 AS DateTime), CAST(0x0000A00C00394FE0 AS DateTime), 30, 1, 1, N'WinLossReport'),
(6, N'System Configuration', N'System Configuration', 0, N'None', N'/SystemSetting/Manage', CAST(0x00009F6C00000000 AS DateTime), CAST(0x0000A38D002D4075 AS DateTime), 100, 1, 1, N'SystemConfiguration'),
(7, N'Racing', N'Racing', 0, N'None', N'/Racing/Main', CAST(0x00009F7B00AE6618 AS DateTime), CAST(0x0000A3C5000F7D40 AS DateTime), 40, 1, 1, N'Racing'),
(8, N'Manage Configuration', N'Manage Configuration', 6, N'System Configuration', N'/SystemSetting/ManageConfiguration', CAST(0x00009F7F00000000 AS DateTime), CAST(0x00009F7F00000000 AS DateTime), 10, 1, 1, N'ManageConfiguration'),
(9, N'Manage Function', N'Manage Function', 6, N'System Configuration', N'/SystemSetting/ManageFunction', CAST(0x00009F7B00000000 AS DateTime), CAST(0x00009FBA00000000 AS DateTime), 20, 1, 1, N'ManageFunction'),
(11, N'Currency Win Loss Report', N'Currency Win Loss Report', 5, N'Win Loss Report', N'/CurrencyWinLoss/Main', CAST(0x00009FAD0036DCEC AS DateTime), CAST(0x0000A3C5000F14B4 AS DateTime), 7, 1, 1, N'CurrencyWinLossReport'),
(12, N'Manage KPI Service', N'Manage KPI Service', 6, N'System Configuration', N'/KPIService/ManageTask', CAST(0x0000A04D00000000 AS DateTime), CAST(0x0000A04D00000000 AS DateTime), 40, 1, 1, N'ManageKPIService'),
(13, N'OANDA Exchange Rate', N'OANDA Exchange Rate', 0, N'None', N'/ExchangeRate/Main', CAST(0x00009EED00000000 AS DateTime), CAST(0x0000A3C5000F8B92 AS DateTime), 50, 1, 1, N'ExchangeRate'),
(14, N'Task Scheduler', N'Task Scheduler', 6, N'System Configuration', N'/TaskScheduler/Index', CAST(0x0000A08500000000 AS DateTime), CAST(0x0000A08500000000 AS DateTime), 50, 1, 1, N'TaskScheduler'),
(15, N'Number Game Win Loss', N'Number Game Win Loss', 5, N'Win Loss Report', N'/NumberGame/Main', CAST(0x0000A0E500EDDAA0 AS DateTime), CAST(0x0000A3C5000F241B AS DateTime), 40, 1, 1, N'NumberGameReport'),
(16, N'Virtual Sports', N'Virtual Sports', 5, N'Win Loss Report', N'/VirtualSports/Main', CAST(0x0000A0E800E78970 AS DateTime), CAST(0x0000A3C5000F333C AS DateTime), 40, 1, 1, N'VirtualSportsReport'),
(17, N'Live Casino Win Loss', N'Live Casino Win Loss', 5, N'Win Loss Report', N'/LiveCasino/Main', CAST(0x0000A101009AE840 AS DateTime), CAST(0x0000A3C5000F4A58 AS DateTime), 40, 1, 1, N'LiveCasinoReport'),
(18, N'Licensee Win Loss', N'Licensee Win Loss', 5, N'Win Loss Report', N'/LicenseeWinLoss/Main', CAST(0x0000A156009450C0 AS DateTime), CAST(0x0000A3C5000EBFEF AS DateTime), 6, 1, 1, N'LicenseeWinLoss'),
(19, N'RNG Casino Win Loss', N'RNG Casino Win Loss', 5, N'Win Loss Report', N'/Report/RngWinLoss', CAST(0x0000A14E009450C0 AS DateTime), CAST(0x0000A14E009450C0 AS DateTime), 40, 1, 1, N'RngWinLossReport'),
(20, N'SunSport Win Loss', N'SunSport Win Loss', 0, N'None', N'/SunSport/Main', CAST(0x0000A28A00000000 AS DateTime), CAST(0x0000A3C500103629 AS DateTime), 60, 1, 1, N'SunSportWinLoss'),
(21, N'Performance', N'Performance', 0, N'None', N'/Report/LicenseePerformance', CAST(0x0000A2DC00000000 AS DateTime), CAST(0x0000A2DC00000000 AS DateTime), 45, 1, 1, N'Performance'),
(22, N'Licensee Performance', N'Performance', 21, N'Performance', N'/Performance/LicenseePerformance', CAST(0x0000A2DC00000000 AS DateTime), CAST(0x0000A3C50018B811 AS DateTime), 11, 1, 1, N'LicenseePerformance'),
(23, N'Performance by Turnover', N'Performance by Turnover', 21, N'Performance', N'/Performance/PerformanceByTurnover', CAST(0x0000A2DC00000000 AS DateTime), CAST(0x0000A3C50018DD35 AS DateTime), 12, 1, 1, N'LicenseePerformancebyTurnOver'),
(24, N'Performance by Licensing Fee', N'Performance by Licensing Fee', 21, N'Performance', N'/Performance/PerformanceByFee', CAST(0x0000A2DC00000000 AS DateTime), CAST(0x0000A3C50018ED41 AS DateTime), 13, 1, 1, N'LicenseePerformancebyLicensingFee'),
(25, N'Performance by Margin', N'Performance by Margin', 21, N'Performance', N'/Performance/PerformanceByMargin', CAST(0x0000A33200000000 AS DateTime), CAST(0x0000A3C50018F997 AS DateTime), 14, 1, 1, N'LicenseePerformancebyMargin'),
(31, N'Licensee Performance in Details', N'Licensee Performance in Details', 21, N'Performance', N'/Performance/LicenseePerformanceDetail', CAST(0x0000A3C5000D89AA AS DateTime), CAST(0x0000A3C5000D89AA AS DateTime), 20, 1, 1, N'LicenseePerformanceDetail')


SET IDENTITY_INSERT [dbo].[LA_Function] OFF
--Group
---Insert data LA_Group
TRUNCATE Table dbo.LA_Group
INSERT INTO dbo.LA_Group (GroupName,GroupDesc,StatusID,ModifyDate,Modifier)
SELECT 'IT User','IT User',1,GETDATE(),1
UNION ALL
SELECT 'Admin User','Admin User',1,GETDATE(),1
UNION ALL
SELECT 'Nomal User','Normal User',1,GETDATE(),1
--Insert to LA_UserFunction

TRUNCATE TABLE LA_UserFunction
DECLARE @strPer Nvarchar(2000)='',@UserID INT
--User_IT
SELECT @strPer = @strPer + FunctionName + ',' FROM LA_Function WITH (NOLOCK)  where ParentID=0
SELECT @UserID = UserID FROM LA_User WITH (NOLOCK)  where Username ='User_IT'

INSERT INTO LA_UserFunction 
SELECT @UserID, FunctionID,Getdate(),1,1 FROM dbo.LA_Function WITH (NOLOCK) 
WHERE FunctionName in (SELECT val FROM dbo.strSplit (@strPer,','))
UNION 
SELECT @UserID, FunctionID,Getdate(),1,1 FROM LA_Function WITH (NOLOCK) 
WHERE ParentID IN (SELECT FunctionID FROM LA_Function WITH (NOLOCK) 
WHERE FunctionName in (SELECT val FROM dbo.strSplit (@strPer,',')))

--User_admin
SELECT @strPer ='Administration,Win Loss Report,Currency Win Loss Report,Number Game Win Loss,
Virtual Sports,Live Casino Win Loss,RNG Casino Win Loss,Racing,Performance,OANDA Exchange Rate'
SELECT @UserID = UserID FROM LA_User where Username ='User_Admin'

INSERT INTO LA_UserFunction 
SELECT @UserID, FunctionID,Getdate(),1,1 FROM dbo.LA_Function WITH (NOLOCK) 
WHERE FunctionName in (SELECT val FROM dbo.strSplit (@strPer,','))
UNION 
SELECT @UserID, FunctionID,Getdate(),1,1 FROM LA_Function WITH (NOLOCK) 
WHERE ParentID IN (SELECT FunctionID FROM LA_Function WITH (NOLOCK) 
WHERE FunctionName in (SELECT val FROM dbo.strSplit (@strPer,',')))
--User_Normal
SELECT @strPer ='Win Loss Report,Currency Win Loss Report,Number Game Win Loss,
Virtual Sports,Live Casino Win Loss,RNG Casino Win Loss,Racing,Performance,OANDA Exchange Rate'
SELECT @UserID = UserID FROM LA_User where Username ='User_Normal'

INSERT INTO LA_UserFunction 
SELECT @UserID, FunctionID,Getdate(),1,1 FROM dbo.LA_Function WITH (NOLOCK) 
WHERE FunctionName in (SELECT val FROM dbo.strSplit (@strPer,','))
UNION 
SELECT @UserID, FunctionID,Getdate(),1,1 FROM LA_Function WITH (NOLOCK) 
WHERE ParentID IN (SELECT FunctionID FROM LA_Function WITH (NOLOCK) 
WHERE FunctionName in (SELECT val FROM dbo.strSplit (@strPer,',')))


--Insert to OA_UserParty
DELETE LA_UserParty
DECLARE @strPer Nvarchar(2000)='',@UserID INT
--User_IT
SELECT @UserID = UserID FROM LA_User where Username ='User_IT'
INSERT INTO LA_UserParty( UserID,PartyID,Modifydate,Modifier,StatusID)
SELECT @UserID,PartyID,getdate(),@UserID,1 
FROM OAS_Party WITH (NOLOCK) WHERE PartyType = 1
--Begin Group area
--LA_GroupFunction
TRUNCATE table LA_GroupFunction
DECLARE @Group INT

SELECT @strPer = @strPer + FunctionName + ',' FROM LA_Function where ParentID=0
SELECT @Group = GroupID FROM LA_Group WITH (NOLOCK)  where GroupName ='IT User'
INSERT INTO LA_GroupFunction 
SELECT @Group, FunctionID FROM LA_Function WITH (NOLOCK) 
WHERE FunctionName in (SELECT val FROM dbo.strSplit (@strPer,','))
UNION 
SELECT @Group, FunctionID FROM LA_Function WITH (NOLOCK) 
WHERE ParentID IN (SELECT FunctionID FROM LA_Function WITH (NOLOCK) 
WHERE FunctionName in (SELECT val FROM dbo.strSplit (@strPer,',')))

--Admin User
--DECLARE @strPer Nvarchar(2000),@Group INT
SELECT @strPer ='Administration,Win Loss Report,Currency Win Loss Report,Number Game Win Loss,
Virtual Sports,Live Casino Win Loss,RNG Casino Win Loss,Racing,Performance,OANDA Exchange Rate'
SELECT @Group = GroupID FROM LA_Group where GroupName ='Admin User'
INSERT INTO LA_GroupFunction 
SELECT @Group, FunctionID FROM LA_Function WITH (NOLOCK) 
WHERE FunctionName in (SELECT val FROM dbo.strSplit (@strPer,','))
UNION 
SELECT @Group, FunctionID FROM LA_Function WITH (NOLOCK) 
WHERE ParentID IN (SELECT FunctionID FROM LA_Function WITH (NOLOCK) 
WHERE FunctionName in (SELECT val FROM dbo.strSplit (@strPer,',')))
--Normal User
--DECLARE @strPer Nvarchar(2000),@Group INT
SELECT @strPer ='Win Loss Report,Currency Win Loss Report,Number Game Win Loss,
Virtual Sports,Live Casino Win Loss,RNG Casino Win Loss,Racing,Performance,OANDA Exchange Rate'
SELECT @Group = GroupID FROM LA_Group where GroupName ='Nomal User'
INSERT INTO LA_GroupFunction 
SELECT @Group, FunctionID FROM LA_Function WITH (NOLOCK) 
WHERE FunctionName in (SELECT val FROM dbo.strSplit (@strPer,','))
UNION 
SELECT @Group, FunctionID FROM LA_Function WITH (NOLOCK) 
WHERE ParentID IN (SELECT FunctionID FROM LA_Function WITH (NOLOCK) 
WHERE FunctionName in (SELECT val FROM dbo.strSplit (@strPer,',')))
--End Group area

--begin Function area
--Insert to LA_FunctionParty
TRUNCATE TABLE La_Functionparty
INSERT INTO La_Functionparty ( Functionid
                                  , Partyid )
SELECT Functionid
              , P.Partyid
      
  FROM Oa_Functionlicensees Fl INNER JOIN Oas_Party P ON Fl.Licenseeid = P.Oldrefid
                                                     AND P.Partytype = 1
GROUP BY Functionid, P.Partyid
/*
--Rebate
DECLARE @HAIFA_ID INT
SELECT @HAIFA_ID = LicenseeID FROM bodb_licensee.dbo.licensees WHERE LicenseeName = 'HAIFA'
INSERT INTO dbo.LA_LicenseeFeeRebate(LicenseeID,FromFee,ToFee,Rate,CurrencyRebate,FromDate,ToDate)
VALUES 
(@HAIFA_ID,NULL,3000000,0,13,NULL,NULL),
(@HAIFA_ID,3000001,5000000,0.05,13,NULL,NULL),
(@HAIFA_ID,5000001,8000000,0.010,13,NULL,NULL),
(@HAIFA_ID,8000001,10000000,0.14,13,NULL,NULL),
(@HAIFA_ID,10000001,12000000,0.18,13,NULL,NULL),
(@HAIFA_ID,12000001,14000000,0.22,13,NULL,NULL),
(@HAIFA_ID,14000001,16000000,0.26,13,NULL,NULL),
(@HAIFA_ID,16000001,18000000,0.30,13,NULL,NULL),
(@HAIFA_ID,18000001,20000000,0.34,13,NULL,NULL),
(@HAIFA_ID,20000001,NULL,0.40,13,NULL,NULL)

INSERT INTO dbo.LA_LicenseeFeeRebate(LicenseeID,FromFee,ToFee,Rate,CurrencyRebate,FromDate,ToDate)
VALUES 
(0,NULL,350000,0,6,NULL,NULL),
(0,350001,650000,0.05,6,NULL,NULL),
(0,650001,950000,0.010,6,NULL,NULL),
(0,950001,1250000,0.14,6,NULL,NULL),
(0,1250001,1500000,0.18,6,NULL,NULL),
(0,1500001,1750000,0.22,6,NULL,NULL),
(0,1750001,2000000,0.26,6,NULL,NULL),
(0,2000001,2250000,0.30,6,NULL,NULL),
(0,2250001,2500000,0.34,6,NULL,NULL),
(0,2500001,NULL,0.40,6,NULL,NULL)
*/