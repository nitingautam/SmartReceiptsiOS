//
//  Database+Trips.h
//  SmartReceipts
//
//  Created by Jaanus Siim on 07/05/15.
//  Copyright (c) 2015 Will Baumann. All rights reserved.
//

#import "Database.h"

@class WBTrip;
@class WBPrice;

@interface Database (Trips)

- (BOOL)createTripsTable;
- (BOOL)saveTrip:(WBTrip *)trip;
- (NSDecimalNumber *)totalPriceForTrip:(WBTrip *)trip;
- (NSArray *)allTrips;
- (WBTrip *)tripWithName:(NSString *)tripName;
- (WBPrice *)updatePriceOfTrip:(WBTrip *)trip;

@end
